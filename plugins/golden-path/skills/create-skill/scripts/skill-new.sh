#!/usr/bin/env bash
# Create the skeleton of a new golden-path skill in the house style.
# Usage: skill-new.sh <name> [--script <file.sh>]
#   <name>     kebab-case; becomes skills/<name>/ and the frontmatter name
#   --script   also create skills/<name>/scripts/<file.sh> with the standard header
#
# Every part to write is marked "FILL:"; skill-lint.sh fails until none is left.
# Never overwrites: refuses a skill that already exists.
# Exit codes: 0 created, 2 usage, 3 the skill already exists
set -euo pipefail

usage() { echo "usage: skill-new.sh <name> [--script <file.sh>]" >&2; exit 2; }

name=""; script=""
while [ $# -gt 0 ]; do
  case "$1" in
    --script) script="${2:-}"; shift 2 ;;
    -*) usage ;;
    *) if [ -n "$name" ]; then usage; fi; name="$1"; shift ;;
  esac
done
[ -n "$name" ] || usage
if [[ ! "$name" =~ ^[a-z][a-z0-9-]*[a-z0-9]$ ]]; then
  echo "skill name '$name' must be kebab-case (lowercase letters, digits, hyphens)" >&2
  exit 2
fi
if [ -n "$script" ] && [[ ! "$script" =~ ^[a-z][a-z0-9-]*\.sh$ ]]; then
  echo "script name '$script' must be kebab-case and end in .sh" >&2
  exit 2
fi

here=$(cd "$(dirname "$0")" && pwd)
plugin=$(cd "$here/../../.." && pwd)
dir="$plugin/skills/$name"
if [ -e "$dir" ]; then
  echo "skills/$name already exists; nothing written" >&2
  exit 3
fi

title=$(tr '-' ' ' <<<"$name")
title="${title^}"
mkdir -p "$dir"

script_step=""
if [ -n "$script" ]; then
  script_step="Run \`bash <skill-dir>/scripts/$script <arguments>\`. FILL: what it does, and a table of its exit codes and what to do for each."
fi

cat >"$dir/SKILL.md" <<EOF
---
name: $name
description: FILL - what the skill does in one sentence, then the triggers. Use when the user asks to ..., or when .... Keep it on one line, without a hash after a space or a colon followed by a space, because YAML would cut the line there.
---

# $title

FILL: one short paragraph. What this procedure achieves and why it exists.

FILL: where its rules live, if it reads any. "The process lives in this plugin, two folders up from this skill: \`../../references/<file>.md\`. Resolve it against this skill's base directory."

FILL: the safety line. What this skill never does, and what needs the user's explicit yes.

## 1. FILL: first step

FILL: what to check or decide first, and when to stop.

## 2. FILL: next step

${script_step:-FILL: the work itself. Anything deterministic (same input, same output) belongs in a script under scripts/, not in prose.}

## 3. Report

Lead with one line: **FILL: the verdict or outcome**.

| Item | Result |
|---|---|
| FILL | FILL |

End with **Not verified:** what couldn't be checked, and one next step.
EOF

if [ -n "$script" ]; then
  mkdir -p "$dir/scripts"
  cat >"$dir/scripts/$script" <<EOF
#!/usr/bin/env bash
# FILL: one line on what this script does for $name.
# Usage: $script <arguments>
#
# Exit codes: 0 ok, 2 usage or missing tool
set -euo pipefail

usage() { echo "usage: $script <arguments>" >&2; exit 2; }
[ \$# -ge 1 ] || usage

echo "FILL: not implemented" >&2
exit 2
EOF
  chmod +x "$dir/scripts/$script"
fi

echo "created skills/$name/SKILL.md$([ -n "$script" ] && echo " and skills/$name/scripts/$script")"
echo "next: replace every FILL: marker, then run skill-lint.sh skills/$name"
