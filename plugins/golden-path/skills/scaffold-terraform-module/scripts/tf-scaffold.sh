#!/usr/bin/env bash
# Create a Terraform module skeleton in the shape the golden-path Terraform standard asks for.
# Usage: tf-scaffold.sh <dir> --description "<one line>" [--provider <source>[@<constraint>]]...
#                             [--terraform-version "<constraint>"]
#   <dir>          folder to create the module in; its last part is the module name (kebab-case)
#   --provider     e.g. bpg/proxmox or "bpg/proxmox@~> 0.117"; repeat for several.
#                  Without a constraint, the one the repo's own versions.tf uses is copied.
#
# Never overwrites: refuses a folder that already has .tf files or a README.md.
# Exit codes: 0 created, 2 usage, 3 folder not empty of Terraform files, 4 a version can't be determined
set -euo pipefail

usage() {
  echo "usage: tf-scaffold.sh <dir> --description \"<one line>\" [--provider <source>[@<constraint>]]... [--terraform-version \"<constraint>\"]" >&2
  exit 2
}

dir=""; description=""; tf_version=""; providers=()
while [ $# -gt 0 ]; do
  case "$1" in
    --description) description="${2:-}"; shift 2 ;;
    --provider) providers+=("${2:-}"); shift 2 ;;
    --terraform-version) tf_version="${2:-}"; shift 2 ;;
    -*) usage ;;
    *) [ -z "$dir" ] || usage; dir="$1"; shift ;;
  esac
done
if [ -z "$dir" ] || [ -z "$description" ]; then usage; fi

name=$(basename "$dir")
if [[ ! "$name" =~ ^[a-z][a-z0-9-]*[a-z0-9]$ ]]; then
  echo "module name '$name' must be kebab-case (lowercase letters, digits, hyphens)" >&2
  exit 2
fi

if [ -d "$dir" ] && { compgen -G "$dir/*.tf" >/dev/null || [ -e "$dir/README.md" ]; }; then
  echo "$dir already has Terraform files or a README.md; nothing written" >&2
  exit 3
fi

# The repo's existing versions.tf files, nearest conventions first (root configs before modules).
mapfile -t existing < <(git ls-files '*versions.tf' 2>/dev/null | grep -v "^${dir#./}/" | awk '{ print (/modules\//) ? "1 " $0 : "0 " $0 }' | sort | cut -d' ' -f2-)

repo_tf_version=""
repo_pins=""   # lines: "<source> <constraint>"
for f in "${existing[@]}"; do
  [ -n "$repo_tf_version" ] || repo_tf_version=$(sed -nE 's/^[[:space:]]*required_version[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/p' "$f" | head -1)
  repo_pins+=$(awk '
    /required_providers/ { inside = 1 }
    inside && /source[[:space:]]*=/  { gsub(/.*=[[:space:]]*"|".*/, ""); src = $0 }
    inside && /version[[:space:]]*=/ { gsub(/.*=[[:space:]]*"|".*/, ""); if (src != "") { print src " " $0; src = "" } }
  ' "$f")$'\n'
done

origin_tf="--terraform-version"
if [ -z "$tf_version" ]; then
  if [ -n "$repo_tf_version" ]; then
    tf_version=$repo_tf_version; origin_tf="the repo's versions.tf"
  elif command -v terraform >/dev/null 2>&1; then
    tf_version="~> $(terraform version 2>/dev/null | head -1 | sed -E 's/^Terraform v([0-9]+\.[0-9]+).*/\1/')"
    origin_tf="the installed Terraform"
  else
    echo "can't determine required_version: no versions.tf in the repo and terraform isn't installed; pass --terraform-version" >&2
    exit 4
  fi
fi

provider_block=""
report=()
for p in "${providers[@]}"; do
  source=${p%%@*}
  constraint=""
  [[ "$p" == *@* ]] && constraint=${p#*@}
  origin="--provider"
  if [ -z "$constraint" ]; then
    constraint=$(awk -v s="$source" '$1 == s { $1 = ""; sub(/^ /, ""); print; exit }' <<<"$repo_pins")
    origin="the repo's versions.tf"
  fi
  if [ -z "$constraint" ]; then
    echo "no version constraint for provider $source: it isn't pinned in the repo; pass --provider \"$source@~> <version>\"" >&2
    exit 4
  fi
  local_name=${source##*/}
  provider_block+="    $local_name = {
      source  = \"$source\"
      version = \"$constraint\"
    }
"
  report+=("provider $source $constraint (from $origin)")
done

mkdir -p "$dir"

if [ -n "$provider_block" ]; then
  cat >"$dir/versions.tf" <<EOF
terraform {
  required_version = "$tf_version"

  required_providers {
$provider_block  }
}
EOF
else
  cat >"$dir/versions.tf" <<EOF
terraform {
  required_version = "$tf_version"
}
EOF
fi

cat >"$dir/variables.tf" <<'EOF'
variable "name" {
  description = "Name of the thing this module creates. Lowercase letters, digits and hyphens."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,61}[a-z0-9]$", var.name))
    error_message = "The name must be kebab-case: lowercase letters, digits and hyphens, starting with a letter."
  }
}
EOF

cat >"$dir/outputs.tf" <<'EOF'
output "name" {
  description = "Name given to the module, for callers that need to refer to it."
  value       = var.name
}
EOF

cat >"$dir/main.tf" <<EOF
# $name: $description
#
# Resources go here. The Terraform standard in short:
# - for_each over count for anything with identity (VMs, nodes)
# - nothing hardcoded: IPs, node names and storage pools come in as variables
# - lifecycle rules only with a comment explaining why
# - no provider block in a module: the calling configuration configures providers
EOF

requirements="| Terraform | \`$tf_version\` |"
for p in "${providers[@]}"; do
  source=${p%%@*}
  constraint=$(sed -nE "/source[[:space:]]*=[[:space:]]*\"${source//\//\\/}\"/{n;s/.*\"([^\"]+)\".*/\1/p}" "$dir/versions.tf")
  requirements+=$'\n'"| \`$source\` | \`$constraint\` |"
done

cat >"$dir/README.md" <<EOF
# $name

$description

## Usage

\`\`\`hcl
module "${name//-/_}" {
  source = "./${dir#./}" # path from the calling configuration

  name = "example"
}
\`\`\`

## Requirements

| Name | Version |
|---|---|
$requirements

## Inputs

| Name | Description | Type | Default |
|---|---|---|---|
| \`name\` | Name of the thing this module creates. Lowercase letters, digits and hyphens. | \`string\` | required |

## Outputs

| Name | Description |
|---|---|
| \`name\` | Name given to the module, for callers that need to refer to it. |
EOF

if command -v terraform >/dev/null 2>&1; then terraform fmt "$dir" >/dev/null 2>&1 || true; fi

echo "created $dir:"
for f in main.tf variables.tf outputs.tf versions.tf README.md; do echo "  $dir/$f"; done
echo "required_version $tf_version (from $origin_tf)"
[ ${#report[@]} -gt 0 ] && printf '%s\n' "${report[@]}"
[ ${#providers[@]} -eq 0 ] && echo "no providers declared: add required_providers to versions.tf when the module uses one"
exit 0
