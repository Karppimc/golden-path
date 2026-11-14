#!/usr/bin/env bash
# Architecture decision records in docs/adr/: create one, and check the folder.
# Usage: adr.sh new "<title>" [--supersedes <number>] [--date <YYYY-MM-DD>]
#        adr.sh check
#
# new    creates docs/adr/NNNN-<slug>.md with the next free number and the standard sections
#        (each to write is marked TO-WRITE), marks a superseded record and links both ways,
#        and rewrites the index docs/adr/README.md. Never overwrites a record.
# check  fails when a record still has TO-WRITE sections or the index is out of step.
#
# Exit codes: 0 ok, 2 usage or not a git repo, 3 a record with that title exists,
#             4 the record to supersede doesn't exist, 10 check found problems
set -euo pipefail

usage() { echo 'usage: adr.sh new "<title>" [--supersedes <number>] [--date <YYYY-MM-DD>] | check' >&2; exit 2; }

cmd="${1:-}"
[ $# -gt 0 ] && shift
root=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "not in a git repo" >&2; exit 2; }
cd "$root"
dir=docs/adr

records() {
  [ -d "$dir" ] || return 0
  find "$dir" -maxdepth 1 -type f -name '[0-9][0-9][0-9][0-9]-*.md' | sort
}
title_of() { sed -nE '1s/^# [0-9]{4}\. //p' "$1"; }
status_of() { sed -nE 's/^- Status: //p' "$1" | head -1; }
date_of() { sed -nE 's/^- Date: //p' "$1" | head -1; }

write_index() {
  {
    echo "# Architecture decision records"
    echo
    echo "One record per decision that shaped this repo: the context, the options considered, the decision and its consequences. Add one with \`/golden-path:write-adr\`; a changed decision gets a new record that supersedes the old one."
    echo
    echo "| # | Decision | Status | Date |"
    echo "|---|---|---|---|"
    while read -r f; do
      [ -n "$f" ] || continue
      base=$(basename "$f")
      # In the index a superseded status keeps its link, pointing at the file next to it.
      echo "| ${base:0:4} | [$(title_of "$f")]($base) | $(status_of "$f") | $(date_of "$f") |"
    done < <(records)
  } >"$dir/README.md"
}

case "$cmd" in
  new)
    title=""; supersedes=""; date=$(date +%F)
    while [ $# -gt 0 ]; do
      case "$1" in
        --supersedes) supersedes="${2:-}"; shift 2 ;;
        --date) date="${2:-}"; shift 2 ;;
        -*) usage ;;
        *) if [ -n "$title" ]; then usage; fi; title="$1"; shift ;;
      esac
    done
    [ -n "$title" ] || usage
    [[ "$date" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || { echo "date must be YYYY-MM-DD" >&2; exit 2; }

    slug=$(tr '[:upper:]' '[:lower:]' <<<"$title" | sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//g' | cut -c1-60 | sed -E 's/-+$//')
    [ -n "$slug" ] || { echo "the title needs letters or digits" >&2; exit 2; }
    if existing=$(records | grep -E "/[0-9]{4}-$slug\.md$"); then
      echo "a record with this title already exists: $existing; nothing written" >&2
      exit 3
    fi

    old=""
    if [ -n "$supersedes" ]; then
      [[ "$supersedes" =~ ^[0-9]{1,4}$ ]] || { echo "--supersedes takes a record number" >&2; exit 2; }
      old=$(records | grep -E "/$(printf '%04d' "$((10#$supersedes))")-" || true)
      [ -n "$old" ] || { echo "no record $(printf '%04d' "$((10#$supersedes))") in $dir to supersede; nothing written" >&2; exit 4; }
    fi

    last=$(records | tail -1 | sed -E 's|.*/([0-9]{4})-.*|\1|')
    number=$(printf '%04d' "$((10#${last:-0} + 1))")
    file="$dir/$number-$slug.md"
    mkdir -p "$dir"

    {
      echo "# $number. $title"
      echo
      echo "- Status: Accepted"
      echo "- Date: $date"
      [ -n "$old" ] && echo "- Supersedes: [$(basename "$old" | cut -c1-4). $(title_of "$old")]($(basename "$old"))"
      cat <<'EOF'

## Context

TO-WRITE: the situation and the forces at play. What made a decision necessary, and what constrained it.

## Options considered

TO-WRITE: only options that were really on the table. For each: what it is, and why it was or wasn't chosen.

## Decision

TO-WRITE: what was decided, in one or two sentences, in the present tense.

## Consequences

TO-WRITE: what follows, good and bad: what becomes easier, what becomes harder, what to revisit and when.

## Sources

TO-WRITE: links to the issue, the pull request and the plan or discussion this record is based on.
EOF
    } >"$file"

    if [ -n "$old" ]; then
      sed -i -E "s|^- Status: .*|- Status: Superseded by [$number. $title]($(basename "$file"))|" "$old"
    fi
    write_index
    echo "created $file"
    [ -n "$old" ] && echo "marked $old as superseded"
    echo "updated $dir/README.md"
    ;;
  check)
    [ $# -eq 0 ] || usage
    problems=0
    if [ -z "$(records)" ]; then echo "no records in $dir"; exit 0; fi
    while read -r f; do
      left=$(grep -c 'TO-WRITE' "$f" || true)
      if [ "$left" -gt 0 ]; then echo "FAIL $f: $left sections still TO-WRITE"; problems=1; fi
      [ -n "$(title_of "$f")" ] || { echo "FAIL $f: first line must be '# NNNN. Title'"; problems=1; }
      [ -n "$(status_of "$f")" ] || { echo "FAIL $f: no '- Status:' line"; problems=1; }
    done < <(records)
    before=$(cat "$dir/README.md" 2>/dev/null || true)
    write_index
    if [ "$before" != "$(cat "$dir/README.md")" ]; then
      echo "FAIL $dir/README.md was out of step with the records (rewritten now: commit it)"; problems=1
    fi
    [ $problems -eq 0 ] && { echo "ok: $(records | wc -l) records, index in step"; exit 0; }
    exit 10
    ;;
  *) usage ;;
esac
