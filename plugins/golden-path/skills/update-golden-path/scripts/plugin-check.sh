#!/usr/bin/env bash
# Release checks for a change to the golden-path plugin itself. Run from the golden-path repo.
# Usage: plugin-check.sh [check]                 report what the change still needs
#        plugin-check.sh bump patch|minor|major  set version in plugin.json from the base version
# Env:   BASE (default origin/main)
#
# Exit codes: 0 nothing to fix / bumped, 2 not the golden-path repo or usage, 10 something to fix
set -uo pipefail

mode="${1:-check}"
level="${2:-}"
base="${BASE:-origin/main}"
plugin=plugins/golden-path
manifest=$plugin/.claude-plugin/plugin.json

usage() { echo "usage: plugin-check.sh [check] | bump patch|minor|major" >&2; exit 2; }
have() { command -v "$1" >/dev/null 2>&1; }

root=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "not in a git repo" >&2; exit 2; }
cd "$root" || exit 2
if [ "$(jq -r .name .claude-plugin/marketplace.json 2>/dev/null)" != golden-path ] || [ ! -f "$manifest" ]; then
  echo "not the golden-path repo (no golden-path marketplace.json and $manifest)" >&2
  exit 2
fi

base_version=$(git show "$base:$manifest" 2>/dev/null | jq -r .version 2>/dev/null)
[ -n "$base_version" ] || base_version=none
version=$(jq -r .version "$manifest")

bumped() {  # bumped <version> <level>
  local maj min pat
  IFS=. read -r maj min pat <<<"$1"
  case "$2" in
    major) echo "$((maj + 1)).0.0" ;;
    minor) echo "$maj.$((min + 1)).0" ;;
    patch) echo "$maj.$min.$((pat + 1))" ;;
  esac
}

if [ "$mode" = bump ]; then
  [[ "$level" =~ ^(patch|minor|major)$ ]] || usage
  [ "$base_version" != none ] || { echo "no base version on $base" >&2; exit 2; }
  new=$(bumped "$base_version" "$level")
  # Edit only the version line, so the rest of plugin.json keeps its formatting.
  sed -i -E "s/(\"version\": *\")[^\"]+\"/\1$new\"/" "$manifest"
  echo "version: $version -> $(jq -r .version "$manifest") ($level from $base_version on $base)"
  exit 0
fi
[ "$mode" = check ] || usage

todo=0
fix() { echo "  FIX: $*"; todo=1; }
skipped=()

# 1. What changed under the plugin, committed on the branch or not yet.
mapfile -t changed < <({ git diff --name-only "$base"...HEAD -- "$plugin"; git status --porcelain -- "$plugin" | cut -c4-; } | sort -u)
mapfile -t skills < <(find "$plugin/skills" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort)
mapfile -t base_skills < <(git ls-tree -d --name-only "$base:$plugin/skills" 2>/dev/null | sort)
added=$(comm -13 <(printf '%s\n' "${base_skills[@]}") <(printf '%s\n' "${skills[@]}") | paste -sd ' ' -)
removed=$(comm -23 <(printf '%s\n' "${base_skills[@]}") <(printf '%s\n' "${skills[@]}") | paste -sd ' ' -)

echo "##### Change against $base"
echo "Files changed under $plugin: ${#changed[@]}"
printf '  %s\n' "${changed[@]}" | head -40
[ -n "$added" ] && echo "Skills added: $added"
[ -n "$removed" ] && echo "Skills removed or renamed: $removed"

# 2. Version.
if [ -n "$removed" ]; then suggest=major
elif [ -n "$added" ]; then suggest=minor
else suggest=patch; fi
echo
echo "##### Version"
echo "Base $base_version, now $version, suggested level: $suggest$([ "$suggest" = major ] && echo ' (removed skill: ask)')"
if [ ${#changed[@]} -eq 0 ]; then
  echo "  ok: plugin unchanged, no bump needed"
elif [ "$version" = "$base_version" ]; then
  fix "plugin changed but version is still $version: run 'plugin-check.sh bump $suggest' (CI fails otherwise)"
elif [ "$(printf '%s\n%s\n' "$base_version" "$version" | sort -V | tail -1)" != "$version" ]; then
  fix "version $version is lower than the base $base_version"
else
  expected=$(bumped "$base_version" "$suggest")
  if [ "$version" = "$expected" ]; then echo "  ok: $base_version -> $version"
  else echo "  note: $base_version -> $version, a $suggest bump would be $expected (fine if chosen on purpose)"; fi
fi

# 3. README in sync with the plugin.
echo
echo "##### README"
mapfile -t rows < <(grep -oE '^\| `/golden-path:[a-z0-9-]+`' README.md | sed -E 's/.*golden-path:([a-z0-9-]+)`/\1/' | sort)
missing=$(comm -23 <(printf '%s\n' "${skills[@]}") <(printf '%s\n' "${rows[@]}") | paste -sd ' ' -)
extra=$(comm -13 <(printf '%s\n' "${skills[@]}") <(printf '%s\n' "${rows[@]}") | paste -sd ' ' -)
[ -n "$missing" ] && fix "skills table lacks: $missing"
[ -n "$extra" ] && fix "skills table lists skills that don't exist: $extra"
[ -z "$missing$extra" ] && echo "  ok: skills table matches ${#skills[@]} skill folders"

count=$(grep -oE '^\*\*[0-9]+ skills' README.md | grep -oE '[0-9]+')
if [ -z "$count" ]; then fix "at-a-glance line '**N skills · ...**' not found"
elif [ "$count" != "${#skills[@]}" ]; then fix "at-a-glance says $count skills, there are ${#skills[@]}"
else echo "  ok: at-a-glance count $count"; fi

words=$(wc -w <"$plugin/references/rules.md")
budget=$(grep -oE 'rules\.md +# ~[0-9]+ words' README.md | grep -oE '[0-9]+' | head -1)
if [ -z "$budget" ]; then fix "rules budget '~N words' not found in the README tree"
elif [ "$words" -gt $((budget * 115 / 100)) ]; then fix "rules.md is $words words, over the ~$budget budget by more than 15%: shorten it or raise the budget on purpose"
else echo "  ok: rules.md $words words, budget ~$budget"; fi

for d in hooks skills scripts references; do
  [ -d "$plugin/$d" ] && ! grep -qE "── $d/" README.md && fix "README tree doesn't show $plugin/$d/"
done

# 4. What CI runs.
echo
echo "##### CI checks, locally"
json_ok=1
for f in .claude-plugin/marketplace.json "$manifest" "$plugin"/hooks/hooks.json; do
  jq empty "$f" 2>/dev/null || { fix "invalid JSON: $f"; json_ok=0; }
done
[ $json_ok -eq 1 ] && echo "  ok: JSON well-formed"

if have shellcheck; then
  if out=$(find plugins -name '*.sh' -print0 | xargs -0 shellcheck 2>&1); then echo "  ok: shellcheck"
  else echo "$out" | sed 's/^/    /' | head -40; fix "shellcheck findings above"; fi
else
  skipped+=("shellcheck (not installed: sudo apt install shellcheck)")
fi

if have claude; then
  for target in . "./$plugin"; do
    if out=$(claude plugin validate "$target" 2>&1); then echo "  ok: claude plugin validate $target"
    else echo "$out" | sed 's/^/    /' | tail -20; fix "claude plugin validate $target failed"; fi
  done
else
  skipped+=("claude plugin validate (claude CLI not installed)")
fi

echo
echo "##### Summary"
if [ $todo -eq 0 ]; then echo "Nothing to fix."; else echo "Fix the FIX lines above."; fi
[ ${#skipped[@]} -gt 0 ] && printf 'Not run: %s\n' "$(printf '%s\n' "${skipped[@]}" | paste -sd ';' - | sed 's/;/; /g')"
[ $todo -eq 0 ] && exit 0
exit 10
