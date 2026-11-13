#!/usr/bin/env bash
# Prints the team rules to stdout; SessionStart stdout is added to Claude's context.
# Runs only in repos owned by an allowed GitHub owner, so other projects stay untouched.
set -euo pipefail

owners="${GOLDEN_PATH_OWNERS:-karppimc}"
project_dir="${CLAUDE_PROJECT_DIR:-$PWD}"
root="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
rules="$root/references/rules.md"

remote="$(git -C "$project_dir" remote get-url origin 2>/dev/null || true)"
[ -n "$remote" ] || exit 0

# GitHub owner names are case-insensitive: compare lowercased.
remote="${remote,,}"
for owner in ${owners//,/ }; do
  case "$remote" in
    *github.com[:/]"${owner,,}"/*)
      if [ -f "$rules" ]; then
        cat "$rules"
        printf '\nPlugin files (references/, scripts/): %s\n' "$root"
      fi
      exit 0
      ;;
  esac
done
exit 0
