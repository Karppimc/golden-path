#!/usr/bin/env bash
# Runs the mechanical Kubernetes checks for review-kubernetes.
# Usage: k8s-checks.sh [--diff] [path ...]   (defaults to the current directory)
# Never applies anything. --diff runs `kubectl diff` against the current context; pass it
# only after the user said yes.
set -uo pipefail

diff_cluster=0
if [ "${1:-}" = "--diff" ]; then diff_cluster=1; shift; fi
paths=("$@")
[ ${#paths[@]} -gt 0 ] || paths=(.)

have() { command -v "$1" >/dev/null 2>&1; }
failures=0
skipped=()
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
section() { printf '\n=== %s\n' "$1"; }
short() { sed "s|$tmp/rendered/||g"; }
result() {
  if [ "$1" -eq 0 ]; then echo "PASS"; else echo "FAIL"; failures=$((failures + 1)); fi
}

# Sort the YAML files: Kubernetes manifests (a document with apiVersion: and kind:),
# Kustomize directories, Helm charts, and other YAML (usually Helm values).
mapfile -t yamls < <(
  for p in "${paths[@]}"; do
    if [ -f "$p" ]; then echo "$p"; else find "$p" \( -name '*.yaml' -o -name '*.yml' \) -not -path '*/.git/*' -not -path '*/charts/*/templates/*'; fi
  done | sort -u
)
manifests=(); others=(); kustom_dirs=(); chart_dirs=(); policies=()
for f in "${yamls[@]}"; do
  base=$(basename "$f")
  case "$base" in
    kustomization.yaml|kustomization.yml) kustom_dirs+=("$(dirname "$f")"); continue ;;
    Chart.yaml) chart_dirs+=("$(dirname "$f")"); continue ;;
  esac
  if grep -qE '^apiVersion:' "$f" && grep -qE '^kind:' "$f"; then
    manifests+=("$f")
    # Kyverno policies, old (kyverno.io ClusterPolicy/Policy) and 1.15+ (policies.kyverno.io *Policy).
    # PolicyExceptions are not policies.
    if grep -qE '^apiVersion: *(policies\.)?kyverno\.io/' "$f" && grep -qE '^kind: *[A-Za-z]*Policy *$' "$f"; then
      policies+=("$f")
    fi
  else
    others+=("$f")
  fi
done

# Manifests inside a Kustomize dir are checked through its render only, not twice.
if [ ${#kustom_dirs[@]} -gt 0 ]; then
  kept=()
  for m in "${manifests[@]}"; do
    inside=0
    for d in "${kustom_dirs[@]}"; do [[ "$m" == "$d"/* ]] && inside=1; done
    [ $inside -eq 0 ] && kept+=("$m")
  done
  manifests=("${kept[@]}")
fi

echo "##### Kubernetes files"
echo "Manifests: ${#manifests[@]} (Kyverno policies: ${#policies[@]})"
echo "Kustomize dirs: ${kustom_dirs[*]:-none}"
echo "Helm charts: ${chart_dirs[*]:-none}"
[ ${#others[@]} -gt 0 ] && echo "Other YAML, not checked as manifests (Helm values?): ${others[*]}"

# Render Kustomize dirs into temp files so they get the same checks as plain manifests.
rendered=()
for d in "${kustom_dirs[@]}"; do
  section "kustomize build $d"
  mkdir -p "$tmp/rendered/$d"
  out_file="$tmp/rendered/$d/kustomize-build.yaml"
  if have kubectl; then
    out=$(kubectl kustomize "$d" 2>&1 >"$out_file"); rc=$?
  elif have kustomize; then
    out=$(kustomize build "$d" 2>&1 >"$out_file"); rc=$?
  else
    skipped+=("kustomize build (neither kubectl nor kustomize installed)"); continue
  fi
  [ -n "$out" ] && echo "$out" | tail -20
  result $rc
  [ $rc -eq 0 ] && rendered+=("$out_file")
done
[ ${#chart_dirs[@]} -gt 0 ] && skipped+=("Helm template rendering for ${chart_dirs[*]}")

targets=("${manifests[@]}" "${rendered[@]}")

if [ ${#targets[@]} -gt 0 ] && have kubeconform; then
  section "kubeconform -strict ($(kubeconform -v 2>&1 | head -1))"
  # Built-in schemas, then the community CRD catalog (Argo CD, Kyverno, cert-manager...).
  out=$(kubeconform -strict -verbose -output json -cache "$tmp" \
    -schema-location default \
    -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' \
    "${targets[@]}" 2>&1); rc=$?
  if jq -e . >/dev/null 2>&1 <<<"$out"; then
    jq -r '.resources[] | select(.status != "statusValid" and .status != "statusEmpty")
      | "\(.status | sub("status"; "") | ascii_downcase): \(.filename) \(.kind)/\(.name) \(.msg)"' <<<"$out" | short
    jq -r '"valid: \([.resources[] | select(.status == "statusValid")] | length), invalid: \([.resources[] | select(.status == "statusInvalid" or .status == "statusError")] | length), no schema: \([.resources[] | select(.status == "statusSkipped")] | length)"' <<<"$out"
  else
    echo "$out" | tail -20
  fi
  result $rc
elif [ ${#targets[@]} -gt 0 ]; then
  skipped+=("kubeconform (not installed)")
fi

if [ ${#targets[@]} -gt 0 ]; then
  section "image tags"
  # image: lines without a tag or digest, or with :latest.
  out=$(grep -nE '^\s*-?\s*image:\s*' "${targets[@]}" 2>/dev/null \
    | grep -vE 'image:\s*["'"'"']?[^"'"'"'[:space:]]+(:[A-Za-z0-9_.-]+|@sha256:[a-f0-9]+)["'"'"']?\s*$' ; \
    grep -nE 'image:\s*["'"'"']?[^[:space:]]+:latest' "${targets[@]}" 2>/dev/null)
  if [ -n "$out" ]; then echo "$out" | short | sort -u; result 1; else echo "all pinned"; result 0; fi
fi

if [ ${#policies[@]} -gt 0 ] && have kyverno; then
  # Repo's own policies: their unit tests, then the manifests checked against them.
  mapfile -t test_dirs < <(for p in "${paths[@]}"; do find "$p" -name 'kyverno-test.yaml' -printf '%h\n' 2>/dev/null; done | sort -u)
  for d in "${test_dirs[@]}"; do
    section "kyverno test $d"
    out=$(kyverno test "$d" 2>&1); rc=$?
    echo "$out" | tail -25
    result $rc
  done
  workloads=()
  for m in "${targets[@]}"; do
    printf '%s\n' "${policies[@]}" | grep -qxF "$m" || workloads+=("$m")
  done
  if [ ${#workloads[@]} -gt 0 ]; then
    section "kyverno apply (repo policies → manifests)"
    res_args=()
    for w in "${workloads[@]}"; do res_args+=(--resource "$w"); done
    out=$(kyverno apply "${policies[@]}" "${res_args[@]}" 2>&1); rc=$?
    echo "$out" | grep -vE '^\s*$' | short | tail -25
    result $rc
  fi
elif [ ${#policies[@]} -gt 0 ]; then
  skipped+=("kyverno test/apply (kyverno not installed)")
fi

if [ $diff_cluster -eq 1 ]; then
  if have kubectl && ctx=$(kubectl config current-context 2>/dev/null); then
    section "kubectl diff (context: $ctx)"
    f_args=()
    for t in "${targets[@]}"; do f_args+=(-f "$t"); done
    out=$(kubectl diff "${f_args[@]}" 2>&1); rc=$?
    echo "$out" | tail -80
    # kubectl diff: 0 no differences, 1 differences found, >1 error.
    if [ $rc -le 1 ]; then echo "$([ $rc -eq 0 ] && echo 'no differences' || echo 'differences shown above')"; else result 1; fi
  else
    skipped+=("kubectl diff (no kubectl or no current context)")
  fi
else
  skipped+=("kubectl diff (needs the user's yes: rerun with --diff)")
fi

echo
echo "##### Summary"
echo "Failed checks: $failures"
if [ ${#skipped[@]} -gt 0 ]; then
  printf 'Not run: %s\n' "$(printf '%s\n' "${skipped[@]}" | sort -u | paste -sd ';' - | sed 's/;/; /g')"
fi
exit 0
