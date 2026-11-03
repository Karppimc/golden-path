#!/usr/bin/env bash
# Runs the mechanical Terraform checks for review-terraform.
# Usage: tf-checks.sh [path ...]   (defaults to the current directory)
# Never runs plan or apply. Leaves no .terraform/ or new lock files behind.
set -uo pipefail

paths=("$@")
[ ${#paths[@]} -gt 0 ] || paths=(.)

mapfile -t dirs < <(
  for p in "${paths[@]}"; do
    if [ -f "$p" ]; then dirname "$p"; else
      find "$p" -name '*.tf' -not -path '*/.terraform/*' -printf '%h\n'
    fi
  done | sort -u
)

if [ ${#dirs[@]} -eq 0 ]; then
  echo "No Terraform files found in: ${paths[*]}"
  exit 0
fi

have() { command -v "$1" >/dev/null 2>&1; }
failures=0
skipped=()
data_dir="$(mktemp -d)"
trap 'rm -rf "$data_dir"' EXIT

section() { printf '\n=== %s: %s\n' "$1" "$2"; }
result() {
  if [ "$1" -eq 0 ]; then echo "PASS"; else echo "FAIL"; failures=$((failures + 1)); fi
}

for d in "${dirs[@]}"; do
  echo
  echo "##### $d"

  if have terraform; then
    section fmt "$d"
    out=$(terraform -chdir="$d" fmt -check -diff -no-color 2>&1); rc=$?
    [ -n "$out" ] && echo "$out"
    result $rc

    section validate "$d"
    had_lock=0; [ -f "$d/.terraform.lock.hcl" ] && had_lock=1
    TF_DATA_DIR="$data_dir/${d//\//_}"
    export TF_DATA_DIR
    out=$(terraform -chdir="$d" init -backend=false -input=false -no-color 2>&1); rc=$?
    if [ $rc -ne 0 ]; then
      echo "init failed (provider download or module source problem):"
      echo "$out" | tail -20
      result 1
    else
      out=$(terraform -chdir="$d" validate -no-color 2>&1); rc=$?
      echo "$out"
      result $rc
    fi
    [ $had_lock -eq 0 ] && rm -f "$d/.terraform.lock.hcl"
    unset TF_DATA_DIR
  else
    skipped+=("terraform fmt/validate (terraform not installed)")
  fi

  if have tflint; then
    section tflint "$d"
    out=$(tflint --chdir="$d" --no-color 2>&1); rc=$?
    [ -n "$out" ] && echo "$out"
    result $rc
  else
    skipped+=("tflint (not installed)")
  fi
done

echo
echo "##### Summary"
echo "Directories checked: ${#dirs[@]}"
echo "Failed checks: $failures"
if [ ${#skipped[@]} -gt 0 ]; then
  printf 'Not run: %s\n' "$(printf '%s\n' "${skipped[@]}" | sort -u | paste -sd ';' - | sed 's/;/; /g')"
fi
exit 0
