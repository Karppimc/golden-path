#!/usr/bin/env bash
# Check golden-path skills against the house style.
# Usage: skill-lint.sh [skill-dir ...]   (defaults to every skill in this plugin)
#
# Exit codes: 0 all skills pass, 2 usage, 10 at least one FAIL
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
plugin=$(cd "$here/../../.." && pwd)

dirs=("$@")
if [ ${#dirs[@]} -eq 0 ]; then
  mapfile -t dirs < <(find "$plugin/skills" -mindepth 1 -maxdepth 1 -type d | sort)
fi

failed=0
for dir in "${dirs[@]}"; do
  dir=${dir%/}
  name=$(basename "$dir")
  file="$dir/SKILL.md"
  problems=()
  bad() { problems+=("$1"); }

  if [ ! -f "$file" ]; then
    echo "FAIL $name"; echo "  no SKILL.md in $dir"; failed=1; continue
  fi

  # Frontmatter: the block between the first two '---' lines.
  [ "$(head -1 "$file")" = "---" ] || bad "SKILL.md must start with a '---' frontmatter line"
  front=$(awk 'NR == 1 && /^---$/ { inside = 1; next } inside && /^---$/ { exit } inside' "$file")
  body=$(awk 'NR == 1 && /^---$/ { inside = 1; next } inside && /^---$/ { inside = 0; started = 1; next } started' "$file")
  [ -n "$body" ] || bad "frontmatter is not closed with '---', or the body is empty"

  fm_name=$(sed -n 's/^name:[[:space:]]*//p' <<<"$front" | head -1)
  [ "$fm_name" = "$name" ] || bad "frontmatter name '$fm_name' must equal the folder name '$name'"
  [[ "$name" =~ ^[a-z][a-z0-9-]*[a-z0-9]$ ]] || bad "folder name must be kebab-case"

  desc=$(sed -n 's/^description:[[:space:]]*//p' <<<"$front" | head -1)
  if [ -z "$desc" ]; then
    bad "frontmatter needs a one-line description"
  else
    if [[ "$desc" != \"* && "$desc" != \'* ]]; then
      # Unquoted YAML: ' #' starts a comment and ': ' starts a mapping, so the rest is lost or the file fails to parse.
      [[ "$desc" == *" #"* ]] && bad "description has ' #': YAML cuts it there (text after it, such as the triggers, is lost). Reword or quote the description"
      [[ "$desc" == *": "* ]] && bad "description has ': ': invalid in an unquoted YAML value. Reword or quote the description"
    fi
    [ ${#desc} -le 1024 ] || bad "description is ${#desc} characters; keep it within 1024"
    grep -qE 'Use (when|in|after|before)' <<<"$desc" || bad "description needs trigger phrases ('Use when ...')"
  fi

  grep -qE '^# [^#]' <<<"$body" || bad "body needs a '# Title' heading"
  mapfile -t steps < <(grep -E '^## [0-9]+[a-z]?\. ' <<<"$body")
  [ ${#steps[@]} -ge 2 ] || bad "needs numbered steps ('## 1. ...', '## 2. ...')"
  if [ ${#steps[@]} -gt 0 ]; then
    grep -qi 'report' <<<"${steps[-1]}" || bad "the last numbered step must be the Report (found '${steps[-1]}')"
  fi
  grep -q 'Not verified' <<<"$body" || bad "the Report must end with 'Not verified'"
  # Skeleton markers ("FILL:" or "FILL -") that were never replaced; a `FILL:` in backticks is prose about the marker.
  # shellcheck disable=SC2016  # the backticks are literal Markdown
  markers=$(sed 's/`FILL:`//g' "$file" | grep -cE 'FILL(:| -)')
  [ "$markers" -eq 0 ] || bad "skeleton markers left: $markers lines with FILL"

  # Scripts the skill mentions must exist; scripts it ships must be mentioned and usable.
  while read -r ref; do
    [ -n "$ref" ] || continue
    base=$(basename "$ref")
    [ -f "$dir/scripts/$base" ] || [ -f "$plugin/scripts/$base" ] || bad "mentions scripts/$base, which is neither in the skill's scripts/ nor in the plugin's scripts/"
  done < <(grep -oE 'scripts/[A-Za-z0-9_.-]+\.sh' "$file" | sort -u)
  if [ -d "$dir/scripts" ]; then
    while read -r script; do
      [ -n "$script" ] || continue
      base=$(basename "$script")
      grep -q "scripts/$base" "$file" || bad "ships scripts/$base but SKILL.md never mentions it"
      [ "$(head -c 2 "$script")" = "#!" ] || bad "scripts/$base has no shebang"
      head -12 "$script" | grep -qiE '^# *usage' || bad "scripts/$base needs a '# Usage:' comment at the top"
    done < <(find "$dir/scripts" -maxdepth 1 -type f -name '*.sh' | sort)
  fi

  # Other skills and references it points at must exist.
  while read -r other; do
    [ -n "$other" ] || continue
    [ -d "$plugin/skills/$other" ] || bad "mentions /golden-path:$other, which is not a skill in this plugin"
  done < <(grep -oE '/golden-path:[a-z0-9-]+' "$file" | sed 's|/golden-path:||' | sort -u)
  while read -r ref; do
    [ -n "$ref" ] || continue
    [ -e "$plugin/${ref#../../}" ] || bad "mentions $ref, which does not exist"
  done < <(grep -oE '\.\./\.\./references/[A-Za-z0-9_./-]+[A-Za-z0-9_/]' "$file" | sort -u)

  if [ ${#problems[@]} -eq 0 ]; then
    echo "ok   $name"
  else
    echo "FAIL $name"
    printf '  %s\n' "${problems[@]}"
    failed=1
  fi
done

[ $failed -eq 0 ] && exit 0
exit 10
