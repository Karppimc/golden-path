#!/usr/bin/env bash
# Generate .github/workflows/validate.yml for the stacks found in the current repo.
# Usage: ci-scaffold.sh [detect]            show what was found and what would be generated
#        ci-scaffold.sh create [options]    write the workflow (and .yamllint if the repo has none)
# Options (create), for tools that aren't installed here:
#   --terraform-version X  --ansible-core-version X  --ansible-lint-version X
#   --yamllint-version X   --kyverno-version X       --kubeconform-version X  --python-version X
#
# One job per stack plus an aggregating "validate" job, the only check a ruleset needs to require.
# Tool versions come from the tools installed here, actions are pinned by commit SHA (resolved
# from GitHub now) and downloaded binaries by checksum. Nothing in the workflow needs credentials.
# Never overwrites: with an existing validate.yml it writes a proposal next to it and shows the diff.
#
# Exit codes: 0 ok, 1 gh / network error, 2 usage or not a git repo, 3 workflow exists (proposal
#             written), 4 a tool version can't be determined, 5 no stack found
set -euo pipefail

usage() { sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }
have() { command -v "$1" >/dev/null 2>&1; }

mode="${1:-detect}"
[ $# -gt 0 ] && shift
[[ "$mode" == detect || "$mode" == create ]] || usage

declare -A ver=()
while [ $# -gt 0 ]; do
  case "$1" in
    --terraform-version|--ansible-core-version|--ansible-lint-version|--yamllint-version|--kyverno-version|--kubeconform-version|--python-version)
      key=${1#--}; key=${key%-version}; ver[$key]="${2:-}"; shift 2 ;;
    *) usage ;;
  esac
done

root=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "not in a git repo" >&2; exit 2; }
cd "$root"
out=.github/workflows/validate.yml

# ---------- detect ----------
mapfile -t tf_dirs < <(git ls-files '*.tf' | xargs -r -n1 dirname | sort -u)
ansible_dir=$(git ls-files 'ansible.cfg' '*/ansible.cfg' | head -1 | xargs -r dirname)
ansible_req=""; ansible_vault=0
if [ -n "$ansible_dir" ]; then
  [ -f "$ansible_dir/requirements.yml" ] && ansible_req=requirements.yml
  grep -qE '^\s*vault_password_file\s*=' "$ansible_dir/ansible.cfg" && ansible_vault=1
fi
mapfile -t kyverno_tests < <(git ls-files '*kyverno-test.yaml' | xargs -r -n1 dirname | sort -u)
# kyverno test walks a folder, so test dirs that share one parent are passed as that parent.
mapfile -t kyverno_parents < <(printf '%s\n' "${kyverno_tests[@]}" | grep -v '^$' | xargs -r -n1 dirname | sort -u)
kyverno_args=("${kyverno_tests[@]}")
if [ ${#kyverno_tests[@]} -gt 1 ] && [ ${#kyverno_parents[@]} -eq 1 ] && [ "${kyverno_parents[0]}" != . ]; then
  kyverno_args=("${kyverno_parents[0]}")
fi
# Manifests: tracked YAML with top-level apiVersion and kind, outside .github, the Ansible dir and Kyverno test fixtures.
mapfile -t manifests < <(
  git ls-files '*.yaml' '*.yml' | grep -vE '^\.github/' | while read -r f; do
    [ -n "$ansible_dir" ] && [[ "$f" == "$ansible_dir"/* ]] && continue
    skip=0
    for t in "${kyverno_tests[@]}"; do [[ "$f" == "$t"/* ]] && skip=1; done
    [ $skip -eq 1 ] && continue
    case "$(basename "$f")" in kustomization.yaml|kustomization.yml|Chart.yaml) continue ;; esac
    grep -qE '^apiVersion:' "$f" && grep -qE '^kind:' "$f" && echo "$f"
  done
)
# A folder is passed whole when every YAML file in it is a manifest; otherwise its manifests one by one.
k8s_targets=()
if [ ${#manifests[@]} -gt 0 ]; then
  while read -r d; do
    total=$(git ls-files "$d/*.yaml" "$d/*.yml" | grep -cE "^$d/[^/]+$" || true)
    inside=$(printf '%s\n' "${manifests[@]}" | grep -cE "^$d/[^/]+$" || true)
    if [ "$total" -eq "$inside" ]; then k8s_targets+=("$d")
    else while read -r f; do k8s_targets+=("$f"); done < <(printf '%s\n' "${manifests[@]}" | grep -E "^$d/[^/]+$"); fi
  done < <(printf '%s\n' "${manifests[@]}" | xargs -n1 dirname | sort -u)
fi
yaml_count=$(git ls-files '*.yaml' '*.yml' | wc -l)
sh_count=$(git ls-files '*.sh' | wc -l)
has_yamllint_cfg=0
for c in .yamllint .yamllint.yml .yamllint.yaml; do [ -f "$c" ] && has_yamllint_cfg=1; done

jobs=()
[ ${#tf_dirs[@]} -gt 0 ] && jobs+=(terraform)
[ "$yaml_count" -gt 0 ] && jobs+=(yamllint)
[ -n "$ansible_dir" ] && jobs+=(ansible)
if [ ${#k8s_targets[@]} -gt 0 ] || [ ${#kyverno_tests[@]} -gt 0 ]; then jobs+=(kubernetes); fi
[ "$sh_count" -gt 0 ] && jobs+=(shellcheck)

echo "repo: $root"
echo "terraform dirs: ${tf_dirs[*]:-none}"
echo "ansible dir: ${ansible_dir:-none}$([ -n "$ansible_req" ] && echo ", collections from requirements.yml")$([ $ansible_vault -eq 1 ] && echo ", vault password file placeholder")"
echo "kubernetes targets: ${k8s_targets[*]:-none}"
echo "kyverno tests: ${kyverno_args[*]:-none}"
echo "yaml files: $yaml_count, shell scripts: $sh_count, yamllint config: $([ $has_yamllint_cfg -eq 1 ] && echo present || echo "none (a .yamllint will be created)")"
echo "jobs: ${jobs[*]:-none} + validate (aggregate)"
if [ ${#jobs[@]} -eq 0 ]; then
  echo "no stack found: nothing to generate"
  exit 5
fi
[ -f "$out" ] && echo "existing workflow: $out (create writes a proposal, not over it)"
[ "$mode" = detect ] && exit 0

# ---------- versions ----------
need() {  # need <key> <how to get it locally>
  local key=$1 found
  [ -n "${ver[$key]:-}" ] && return 0
  found=$(eval "$2" 2>/dev/null || true)
  if [ -z "$found" ]; then
    echo "can't determine the $key version: the tool isn't installed here. Pass --$key-version <version>." >&2
    exit 4
  fi
  ver[$key]=$found
}
uses() { [[ " ${jobs[*]} " == *" $1 "* ]]; }

if uses terraform; then need terraform "terraform version | head -1 | sed -E 's/^Terraform v//'"; fi
if uses yamllint || uses ansible; then need python "python3 --version | sed -E 's/^Python ([0-9]+\.[0-9]+).*/\1/'"; fi
if uses yamllint; then need yamllint "yamllint --version | awk '{print \$2}'"; fi
if uses ansible; then
  need ansible-lint "ansible-lint --version | head -1 | sed 's/\x1b\[[0-9;]*m//g' | awk '{print \$2}'"
  need ansible-core "ansible-lint --version | head -1 | sed 's/\x1b\[[0-9;]*m//g' | sed -E 's/.*ansible-core:([0-9.]+).*/\1/'"
fi
if uses kubernetes; then
  [ ${#k8s_targets[@]} -gt 0 ] && need kubeconform "kubeconform -v | sed 's/^v//'"
  [ ${#kyverno_tests[@]} -gt 0 ] && need kyverno "kyverno version | sed -nE 's/^Version: *v?//p' | head -1"
fi

# ---------- pins from GitHub ----------
pin() {  # pin <owner/repo> -> "<sha> # <tag>"
  local tag sha
  tag=$(gh api "repos/$1/releases/latest" --jq .tag_name) || exit 1
  sha=$(gh api "repos/$1/commits/$tag" --jq .sha) || exit 1
  echo "$sha # $tag"
}
checksum() {  # checksum <url of checksums file> <asset name>
  local sum
  sum=$(curl -fsSL "$1" | awk -v a="$2" '$2 == a { print $1 }') || exit 1
  [ -n "$sum" ] || { echo "no checksum for $2 in $1" >&2; exit 1; }
  echo "$sum"
}
have gh || { echo "missing tool: gh" >&2; exit 2; }
checkout=$(pin actions/checkout)
runner=ubuntu-24.04

# ---------- generate ----------
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
{
  cat <<'EOF'
---
# Static checks for every stack in the repo. Nothing here needs credentials.
#
# The ruleset on main requires one check: "validate". It passes only when
# every other job passed, so jobs can be added or renamed without touching the
# ruleset.
#
# Generated by golden-path scaffold-ci-workflow; edit freely afterwards.
name: validate

on:
  pull_request:
    branches: [main]
  push:
    branches: [main]

permissions:
  contents: read

concurrency:
  group: validate-${{ github.ref }}
  cancel-in-progress: true

env:
EOF
  uses terraform && echo "  TERRAFORM_VERSION: ${ver[terraform]}"
  if uses yamllint || uses ansible; then echo "  PYTHON_VERSION: \"${ver[python]}\""; fi
  if uses ansible; then
    echo "  ANSIBLE_CORE_VERSION: ${ver[ansible-core]}"
    echo "  ANSIBLE_LINT_VERSION: ${ver[ansible-lint]}"
  fi
  uses yamllint && echo "  YAMLLINT_VERSION: ${ver[yamllint]}"
  if uses kubernetes; then
    if [ ${#kyverno_tests[@]} -gt 0 ]; then
      kv="v${ver[kyverno]}"
      echo "  # Keep the same version as the Kyverno running in the cluster"
      echo "  KYVERNO_VERSION: $kv"
      echo "  KYVERNO_SHA256: $(checksum "https://github.com/kyverno/kyverno/releases/download/$kv/checksums.txt" "kyverno-cli_${kv}_linux_x86_64.tar.gz")"
    fi
    if [ ${#k8s_targets[@]} -gt 0 ]; then
      cv="v${ver[kubeconform]}"
      echo "  KUBECONFORM_VERSION: $cv"
      echo "  KUBECONFORM_SHA256: $(checksum "https://github.com/yannh/kubeconform/releases/download/$cv/CHECKSUMS" "kubeconform-linux-amd64.tar.gz")"
      echo "  # CRD schemas (Argo CD, Kyverno...) come from datreeio/CRDs-catalog, pinned to a commit"
      echo "  CRD_CATALOG_REF: $(gh api repos/datreeio/CRDs-catalog/commits/main --jq .sha)"
    fi
  fi

  echo
  echo "jobs:"

  if uses terraform; then
    setup_tf=$(pin hashicorp/setup-terraform)
    cat <<EOF
  terraform:
    name: terraform
    runs-on: $runner
    steps:
      - uses: actions/checkout@$checkout
      - uses: hashicorp/setup-terraform@$setup_tf
        with:
          terraform_version: \${{ env.TERRAFORM_VERSION }}
          terraform_wrapper: false
      - name: terraform fmt
        run: terraform fmt -check -recursive -diff
      # No backend and no variables: validate only needs the provider schema
      - name: terraform init and validate
        run: |
          for dir in ${tf_dirs[*]}; do
            echo "::group::\${dir}"
            terraform -chdir="\${dir}" init -backend=false -input=false
            terraform -chdir="\${dir}" validate
            echo "::endgroup::"
          done

EOF
  fi

  if uses yamllint || uses ansible; then setup_py=$(pin actions/setup-python); fi

  if uses yamllint; then
    cat <<EOF
  yamllint:
    name: yamllint
    runs-on: $runner
    steps:
      - uses: actions/checkout@$checkout
      - uses: actions/setup-python@$setup_py
        with:
          python-version: \${{ env.PYTHON_VERSION }}
      - name: Install yamllint
        run: pip install "yamllint==\${YAMLLINT_VERSION}"
      - name: yamllint
        run: yamllint .

EOF
  fi

  if uses ansible; then
    cat <<EOF
  ansible:
    name: ansible
    runs-on: $runner
    defaults:
      run:
        working-directory: $ansible_dir
    steps:
      - uses: actions/checkout@$checkout
      - uses: actions/setup-python@$setup_py
        with:
          python-version: \${{ env.PYTHON_VERSION }}
      - name: Install ansible-lint
        run: >-
          pip install
          "ansible-core==\${ANSIBLE_CORE_VERSION}"
          "ansible-lint==\${ANSIBLE_LINT_VERSION}"
EOF
    if [ -n "$ansible_req" ]; then
      cat <<EOF
      - name: Install collections
        run: ansible-galaxy collection install -r $ansible_req
EOF
    fi
    if [ $ansible_vault -eq 1 ]; then
      cat <<'EOF'
      # ansible.cfg points at a vault password file that only exists on the
      # workstation. The syntax check never decrypts vaulted files, so a
      # placeholder is enough and the real password stays out of GitHub.
      - name: ansible-lint
        run: |
          echo "placeholder-not-a-secret" > "${RUNNER_TEMP}/vault-pass"
          ANSIBLE_VAULT_PASSWORD_FILE="${RUNNER_TEMP}/vault-pass" ansible-lint

EOF
    else
      cat <<'EOF'
      - name: ansible-lint
        run: ansible-lint

EOF
    fi
  fi

  if uses kubernetes; then
    cat <<EOF
  kubernetes:
    name: kubernetes
    runs-on: $runner
    steps:
      - uses: actions/checkout@$checkout
      - name: Install tools
        working-directory: \${{ runner.temp }}
        run: |
          mkdir -p "\${RUNNER_TEMP}/bin"
EOF
    if [ ${#k8s_targets[@]} -gt 0 ]; then
      cat <<'EOF'
          curl -fsSLo kubeconform.tar.gz \
            "https://github.com/yannh/kubeconform/releases/download/${KUBECONFORM_VERSION}/kubeconform-linux-amd64.tar.gz"
          echo "${KUBECONFORM_SHA256}  kubeconform.tar.gz" | sha256sum -c -
          tar -xzf kubeconform.tar.gz -C "${RUNNER_TEMP}/bin" kubeconform
EOF
    fi
    if [ ${#kyverno_tests[@]} -gt 0 ]; then
      cat <<'EOF'
          curl -fsSLo kyverno.tar.gz \
            "https://github.com/kyverno/kyverno/releases/download/${KYVERNO_VERSION}/kyverno-cli_${KYVERNO_VERSION}_linux_x86_64.tar.gz"
          echo "${KYVERNO_SHA256}  kyverno.tar.gz" | sha256sum -c -
          tar -xzf kyverno.tar.gz -C "${RUNNER_TEMP}/bin" kyverno
EOF
    fi
    cat <<'EOF'
          echo "${RUNNER_TEMP}/bin" >> "${GITHUB_PATH}"
EOF
    if [ ${#k8s_targets[@]} -gt 0 ]; then
      cat <<EOF
      # Only folders and files that hold Kubernetes resources: Helm values
      # files are not manifests. Add new manifest folders here.
      - name: kubeconform
        run: >-
          kubeconform -strict -summary
          -schema-location default
          -schema-location
          "https://raw.githubusercontent.com/datreeio/CRDs-catalog/\${CRD_CATALOG_REF}/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json"
          ${k8s_targets[*]}
EOF
    fi
    if [ ${#kyverno_tests[@]} -gt 0 ]; then
      cat <<EOF
      - name: kyverno test
        run: kyverno test ${kyverno_args[*]}
EOF
    fi
    echo
  fi

  if uses shellcheck; then
    cat <<EOF
  shellcheck:
    name: shellcheck
    runs-on: $runner
    steps:
      - uses: actions/checkout@$checkout
      # shellcheck is preinstalled on GitHub's Ubuntu runners
      - name: shellcheck
        run: git ls-files -z '*.sh' | xargs -0 shellcheck

EOF
  fi

  needs=$(printf '%s, ' "${jobs[@]}")
  needs=${needs%, }
  cat <<EOF
  # The only required check. "if: always()" matters: a skipped job counts as
  # passed for a required check, so this job must run and fail explicitly when
  # a dependency failed or was cancelled.
  validate:
    name: validate
    if: always()
    needs: [$needs]
    runs-on: $runner
    steps:
      - name: Check job results
        env:
          RESULTS: \${{ join(needs.*.result, ' ') }}
        run: |
          echo "Job results: \${RESULTS}"
          for result in \${RESULTS}; do
            if [ "\${result}" != "success" ]; then
              echo "::error::A validate job did not succeed"
              exit 1
            fi
          done
EOF
} >"$tmp"

if uses yamllint && [ $has_yamllint_cfg -eq 0 ]; then
  cat >.yamllint <<'EOF'
---
# Moderate defaults: yamllint's own (80 columns, mandatory "---") fail most
# real repos. Tighten per repo when wanted.
extends: default
rules:
  line-length:
    max: 160
  document-start: disable
  truthy:
    check-keys: false
  comments:
    min-spaces-from-content: 1
EOF
  echo "created .yamllint"
fi

if [ -f "$out" ]; then
  proposal="${out%.yml}.proposed.yml"
  cp "$tmp" "$proposal"
  echo "$out exists; proposal written to $proposal (don't commit it as is: merge what you want, then delete it)"
  diff -u "$out" "$proposal" | head -200 || true
  exit 3
fi
mkdir -p "$(dirname "$out")"
cp "$tmp" "$out"
echo "created $out"
echo "required check for the ruleset: validate"
