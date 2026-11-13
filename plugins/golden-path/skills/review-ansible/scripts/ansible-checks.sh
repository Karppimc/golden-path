#!/usr/bin/env bash
# Runs the mechanical Ansible checks for review-ansible.
# Usage: ansible-checks.sh [path ...]   (defaults to the current directory)
# Never runs a playbook against hosts: only ansible-lint, yamllint and --syntax-check.
# Runs from the directory holding ansible.cfg so its inventory and roles path apply.
set -uo pipefail

paths=("$@")
[ ${#paths[@]} -gt 0 ] || paths=(.)

have() { command -v "$1" >/dev/null 2>&1; }

# The Ansible project root: nearest ansible.cfg at or above the first path, else below it.
find_root() {
  local d
  d=$(cd "$(dirname "$1")" 2>/dev/null && pwd); [ -d "$1" ] && d=$(cd "$1" && pwd)
  while [ -n "$d" ] && [ "$d" != / ]; do
    [ -f "$d/ansible.cfg" ] && { echo "$d"; return; }
    d=$(dirname "$d")
  done
  find "$1" -name ansible.cfg -not -path '*/.ansible/*' -printf '%h\n' 2>/dev/null | head -1
}

root=$(find_root "${paths[0]}")
if [ -z "$root" ]; then
  if [ -d "${paths[0]}" ]; then root=$(cd "${paths[0]}" && pwd); else root=$(pwd); fi
  echo "No ansible.cfg found; running from $root"
fi

# Targets relative to the root, so they resolve after cd and print short.
targets=()
for p in "${paths[@]}"; do
  targets+=("$(realpath --relative-to="$root" "$p")")
done
cd "$root" || exit 1

# Playbooks: YAML files whose top level is a list (first content line starts with "- ")
# and whose plays have hosts: or import_playbook:. Inventories and vars files are mappings.
is_playbook() {
  local first
  first=$(grep -vE '^\s*(#|$|---)' "$1" 2>/dev/null | head -1)
  [[ "$first" == "- "* ]] && grep -qE '^(- +|  +)(hosts|import_playbook|ansible\.builtin\.import_playbook):' "$1"
}
mapfile -t playbooks < <(
  for t in "${targets[@]}"; do
    if [ -f "$t" ]; then echo "$t"; else find "$t" \( -name '*.yml' -o -name '*.yaml' \) -not -path '*/.ansible/*' -not -path '*/roles/*'; fi
  done | sort -u | while read -r f; do
    is_playbook "$f" && echo "$f"
  done
)

# Collections from requirements.yml go to a temp dir, never into the project, so lint and
# syntax-check can resolve their modules. Needs network; reported if it fails.
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
req=""
for r in requirements.yml collections/requirements.yml; do [ -f "$r" ] && { req=$r; break; }; done

failures=0
skipped=()
had_dot_ansible=0; [ -d .ansible ] && had_dot_ansible=1
section() { printf '\n=== %s\n' "$1"; }
result() {
  if [ "$1" -eq 0 ]; then echo "PASS"; else echo "FAIL"; failures=$((failures + 1)); fi
}

echo "##### Ansible project: $root"
echo "Targets: ${targets[*]}"
echo "Playbooks: ${playbooks[*]:-none}"

if [ -n "$req" ] && have ansible-galaxy; then
  section "collections from $req (temp dir)"
  # --force: install into the temp dir even when the ansible package bundles the collection,
  # because ansible-lint often lives in another venv and can't see that copy.
  if out=$(ansible-galaxy collection install --force -r "$req" -p "$tmp/collections" 2>&1); then
    export ANSIBLE_COLLECTIONS_PATH="$tmp/collections:${ANSIBLE_COLLECTIONS_PATH:-}"
    grep -E 'was installed successfully|already installed' <<<"$out" | sed 's/^/  /'
  else
    echo "$out" | tail -5
    skipped+=("collections from $req (install failed: modules from them show as unknown)")
  fi
fi

if have ansible-lint; then
  section "ansible-lint ($(ansible-lint --version 2>/dev/null | head -1 | sed 's/\x1b\[[0-9;]*m//g'))"
  # --offline: don't install collections from requirements.yml into the project.
  out=$(ansible-lint --offline --nocolor -f pep8 "${targets[@]}" 2>&1); rc=$?
  [ -n "$out" ] && echo "$out" | grep -vE '^(WARNING  Listing|INFO|$)' | tail -60
  result $rc
else
  skipped+=("ansible-lint (not installed)")
fi

if have yamllint; then
  cfg="default config (line-length 80): no .yamllint in the project"
  for c in .yamllint .yamllint.yml .yamllint.yaml ../.yamllint ../.yamllint.yml ../.yamllint.yaml; do
    [ -f "$c" ] && { cfg="config: $c"; break; }
  done
  section "yamllint ($cfg)"
  out=$(yamllint -f parsable "${targets[@]}" 2>&1); rc=$?
  [ -n "$out" ] && echo "$out" | tail -60
  echo "errors: $(grep -c '\[error\]' <<<"$out") warnings: $(grep -c '\[warning\]' <<<"$out")"
  result $rc
else
  skipped+=("yamllint (not installed)")
fi

if have ansible-playbook; then
  for pb in "${playbooks[@]}"; do
    section "syntax-check ${pb#"$root"/}"
    out=$(ansible-playbook --syntax-check "$pb" 2>&1); rc=$?
    if [ $rc -ne 0 ] && grep -qiE 'vault (secrets|password)|decrypt' <<<"$out"; then
      echo "needs the vault password; not checked"
      skipped+=("syntax-check ${pb#"$root"/} (vault-encrypted vars)")
      continue
    fi
    [ $rc -ne 0 ] && echo "$out" | tail -20
    result $rc
  done
else
  skipped+=("ansible-playbook --syntax-check (ansible-core not installed)")
fi

# ansible-lint may create .ansible/ in the project; leave the tree as we found it.
if [ $had_dot_ansible -eq 0 ] && [ -d .ansible ]; then
  find .ansible -mindepth 0 -delete 2>/dev/null
fi

echo
echo "##### Summary"
echo "Playbooks syntax-checked: ${#playbooks[@]}"
echo "Failed checks: $failures"
if [ ${#skipped[@]} -gt 0 ]; then
  printf 'Not run: %s\n' "$(printf '%s\n' "${skipped[@]}" | sort -u | paste -sd ';' - | sed 's/;/; /g')"
fi
exit 0
