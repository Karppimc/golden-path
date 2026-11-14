#!/usr/bin/env bash
# Create a Kyverno validating policy and its tests in the repo's own pattern.
# Usage: kyverno-scaffold.sh <name> --description "<what it prevents and why>"
#                            [--policy-dir <dir>] [--test-dir <dir>] [--api new|classic]
#   <name>        kebab-case, e.g. require-standard-labels
#   --policy-dir  where policies live; default: the folder of the repo's existing policies, else policies/
#   --test-dir    root of the policy tests; default: the repo's existing one, else tests/policies/
#   --api         new = policies.kyverno.io ValidatingPolicy (CEL), classic = kyverno.io ClusterPolicy;
#                 default: what the repo's policies use, else new
#
# The policy starts in Audit and carries one working example rule (pods need the
# app.kubernetes.io/name label) with a good, a bad and an excluded test pod, so `kyverno test`
# passes before anything is edited. Never overwrites an existing policy or test.
#
# Exit codes: 0 created (and tests passed, when kyverno is installed), 2 usage or not a git repo,
#             3 the policy or its test folder exists, 10 created but `kyverno test` failed
set -euo pipefail

usage() { sed -n '3,4p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }

name=""; description=""; policy_dir=""; test_root=""; api=""
while [ $# -gt 0 ]; do
  case "$1" in
    --description) description="${2:-}"; shift 2 ;;
    --policy-dir) policy_dir="${2:-}"; shift 2 ;;
    --test-dir) test_root="${2:-}"; shift 2 ;;
    --api) api="${2:-}"; shift 2 ;;
    -*) usage ;;
    *) if [ -n "$name" ]; then usage; fi; name="$1"; shift ;;
  esac
done
if [ -z "$name" ] || [ -z "$description" ]; then usage; fi
if [[ ! "$name" =~ ^[a-z][a-z0-9-]*[a-z0-9]$ ]]; then
  echo "policy name '$name' must be kebab-case (lowercase letters, digits, hyphens)" >&2
  exit 2
fi
if [ -n "$api" ] && [[ "$api" != new && "$api" != classic ]]; then usage; fi

root=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "not in a git repo" >&2; exit 2; }
cd "$root"

# The repo's existing policies decide the folder, the API and the excluded namespaces.
mapfile -t existing < <(
  # Tracked and not-yet-added files, so a policy written a moment ago counts too.
  git ls-files -co --exclude-standard '*.yaml' '*.yml' | while read -r f; do
    grep -qE '^apiVersion: *(policies\.)?kyverno\.io/' "$f" && grep -qE '^kind: *[A-Za-z]*Policy *$' "$f" && echo "$f"
  done
)
origin_dir="--policy-dir"; origin_api="--api"; origin_test="--test-dir"
if [ -z "$policy_dir" ]; then
  if [ ${#existing[@]} -gt 0 ]; then policy_dir=$(dirname "${existing[0]}"); origin_dir="the repo's policies"
  else policy_dir=policies; origin_dir="default"; fi
fi
if [ -z "$api" ]; then
  if [ ${#existing[@]} -eq 0 ]; then api=new; origin_api="default"
  elif grep -qE '^apiVersion: *policies\.kyverno\.io/' "${existing[@]}"; then api=new; origin_api="the repo's policies"
  else api=classic; origin_api="the repo's policies"; fi
fi
if [ -z "$test_root" ]; then
  first_test=$(git ls-files -co --exclude-standard '*kyverno-test.yaml' | head -1)
  if [ -n "$first_test" ]; then test_root=$(dirname "$(dirname "$first_test")"); origin_test="the repo's tests"
  else test_root=tests/policies; origin_test="default"; fi
fi
excluded="kube-system, kyverno"
if [ ${#existing[@]} -gt 0 ]; then
  found=$(grep -hoE 'values: *\[[a-z0-9, -]+\]' "${existing[@]}" 2>/dev/null | head -1 | sed -E 's/values: *\[//; s/\]//') || true
  [ -n "${found:-}" ] && excluded=$found
fi
first_excluded=${excluded%%,*}

policy="$policy_dir/$name.yaml"
test_dir="$test_root/$name"
if [ -e "$policy" ] || [ -e "$test_dir" ]; then
  echo "$policy or $test_dir already exists; nothing written" >&2
  exit 3
fi
mkdir -p "$policy_dir" "$test_dir"
rel=$(realpath --relative-to="$test_dir" "$policy")
title=$(tr '-' ' ' <<<"$name"); title="${title^}"
comment=$(fold -s -w 78 <<<"$description" | sed 's/[[:space:]]*$//; s/^/# /')

if [ "$api" = new ]; then
  cat >"$policy" <<EOF
$comment
apiVersion: policies.kyverno.io/v1
kind: ValidatingPolicy
metadata:
  name: $name
  annotations:
    policies.kyverno.io/title: $title
    policies.kyverno.io/severity: medium
spec:
  # New policies start in Audit: violations show up in PolicyReports and nothing is
  # rejected. Change to [Deny, Audit] only once the reports are clean or every finding
  # has a narrow, documented exception.
  # Fail closed: if Kyverno is down, matching resources are rejected rather than
  # admitted unchecked (the namespaces below are excluded, so the cluster can recover)
  failurePolicy: Fail
  validationActions: [Audit]
  evaluation:
    background:
      enabled: true
  matchConstraints:
    resourceRules:
      - apiGroups: [""]
        apiVersions: [v1]
        operations: [CREATE, UPDATE]
        resources: [pods]
    namespaceSelector:
      matchExpressions:
        - key: kubernetes.io/metadata.name
          operator: NotIn
          values: [$excluded]
  validations:
    # Example rule: replace the expression and the message with the real ones
    - expression: >-
        object.metadata.?labels[?'app.kubernetes.io/name'].hasValue()
      message: Every pod must have the app.kubernetes.io/name label.
EOF
  cat >"$test_dir/kyverno-test.yaml" <<EOF
apiVersion: cli.kyverno.io/v1alpha1
kind: Test
metadata:
  name: $name
policies:
  - $rel
resources:
  - resources.yaml
results:
  - policy: $name
    isValidatingPolicy: true
    kind: Pod
    result: pass
    resources:
      - good-with-label
  - policy: $name
    isValidatingPolicy: true
    kind: Pod
    result: fail
    resources:
      - bad-no-labels
      - bad-other-label-only
  # Excluded by the namespaceSelector: the policy produces no result at all
  - policy: $name
    isValidatingPolicy: true
    kind: Pod
    result: skip
    resources:
      - excluded-$first_excluded
EOF
else
  cat >"$policy" <<EOF
$comment
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: $name
  annotations:
    policies.kyverno.io/title: $title
    policies.kyverno.io/severity: medium
spec:
  background: true
  rules:
    - name: $name
      match:
        any:
          - resources:
              kinds: [Pod]
      exclude:
        any:
          - resources:
              namespaces: [$excluded]
      validate:
        # New policies start in Audit: violations show up in PolicyReports and nothing
        # is rejected. Change to Enforce only once the reports are clean or every
        # finding has a narrow, documented exception.
        failureAction: Audit
        # Example rule: replace the pattern and the message with the real ones
        message: Every pod must have the app.kubernetes.io/name label.
        pattern:
          metadata:
            labels:
              app.kubernetes.io/name: "?*"
EOF
  cat >"$test_dir/kyverno-test.yaml" <<EOF
apiVersion: cli.kyverno.io/v1alpha1
kind: Test
metadata:
  name: $name
policies:
  - $rel
resources:
  - resources.yaml
results:
  - policy: $name
    rule: $name
    kind: Pod
    result: pass
    resources:
      - good-with-label
  - policy: $name
    rule: $name
    kind: Pod
    result: fail
    resources:
      - bad-no-labels
      - bad-other-label-only
  # Excluded by the rule's exclude block
  - policy: $name
    rule: $name
    kind: Pod
    result: skip
    resources:
      - excluded-$first_excluded
EOF
fi

cat >"$test_dir/resources.yaml" <<EOF
# Test pods for $name. Never applied to a cluster: they exist only for
# \`kyverno test\`. Keep at least one good, one bad and one excluded resource.
---
apiVersion: v1
kind: Pod
metadata:
  name: good-with-label
  namespace: demo
  labels:
    app.kubernetes.io/name: app
spec:
  containers:
    - name: app
      image: ghcr.io/example/app:1.0.0
---
apiVersion: v1
kind: Pod
metadata:
  name: bad-no-labels
  namespace: demo
spec:
  containers:
    - name: app
      image: ghcr.io/example/app:1.0.0
---
apiVersion: v1
kind: Pod
metadata:
  name: bad-other-label-only
  namespace: demo
  labels:
    team: platform
spec:
  containers:
    - name: app
      image: ghcr.io/example/app:1.0.0
---
# In an excluded namespace: the policy must not evaluate it at all
apiVersion: v1
kind: Pod
metadata:
  name: excluded-$first_excluded
  namespace: $first_excluded
spec:
  containers:
    - name: app
      image: ghcr.io/example/app:1.0.0
EOF

echo "created $policy ($api API from $origin_api, folder from $origin_dir, starts in Audit)"
echo "created $test_dir/kyverno-test.yaml and resources.yaml (test folder from $origin_test)"
echo "excluded namespaces: $excluded"
if command -v kyverno >/dev/null 2>&1; then
  if out=$(kyverno test "$test_dir" 2>&1); then
    echo "kyverno test: $(grep -E 'Test Summary' <<<"$out" | sed 's/^Test Summary: //')"
  else
    echo "$out" | tail -25
    echo "kyverno test FAILED on the untouched skeleton: a bug in this script, or a kyverno CLI that doesn't know this API"
    exit 10
  fi
else
  echo "kyverno test: not run (kyverno CLI not installed)"
fi
echo "next: replace the example rule in $policy and the pods in $test_dir/resources.yaml"
