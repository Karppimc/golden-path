#!/usr/bin/env bash
# Move an issue's card to a column on every open GitHub Projects board the issue is on.
# The board is found at run time from the issue itself; nothing is hardcoded.
#
# Usage: board-move.sh <issue-number> [column]     column defaults to "Review"
# Env:   GOLDEN_PATH_STATUS_FIELD                   single-select field name, defaults to "Status"
#
# Exit codes:
#   0  moved, or already in the column, on every board
#   1  gh / API error (missing `project` scope, no network, not logged in...)
#   2  usage error or missing tool
#   3  the issue is not on any open board
#   4  a board has no such field or column
set -euo pipefail

issue="${1:-}"
column="${2:-Review}"
field="${GOLDEN_PATH_STATUS_FIELD:-Status}"

if [[ ! "$issue" =~ ^[0-9]+$ ]]; then
  echo "usage: board-move.sh <issue-number> [column]" >&2
  exit 2
fi
for tool in gh jq; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "missing tool: $tool" >&2
    exit 2
  fi
done

nwo=$(gh repo view --json nameWithOwner --jq .nameWithOwner) || exit 1
owner="${nwo%/*}"
repo="${nwo#*/}"

# shellcheck disable=SC2016  # $vars below are GraphQL variables, not shell
query='
query($owner: String!, $repo: String!, $number: Int!, $field: String!) {
  repository(owner: $owner, name: $repo) {
    issue(number: $number) {
      projectItems(first: 20) {
        nodes {
          id
          project {
            id
            number
            title
            closed
            field(name: $field) {
              ... on ProjectV2SingleSelectField { id options { id name } }
            }
          }
          fieldValueByName(name: $field) {
            ... on ProjectV2ItemFieldSingleSelectValue { name }
          }
        }
      }
    }
  }
}'

if ! response=$(gh api graphql -f query="$query" -f owner="$owner" -f repo="$repo" \
  -F number="$issue" -f field="$field" 2>&1); then
  echo "$response" >&2
  if grep -qiE 'scope|INSUFFICIENT' <<<"$response"; then
    echo "hint: the gh token needs the 'project' scope. Run: gh auth refresh -s project" >&2
  fi
  exit 1
fi

# One TSV row per open board: item id, project id, number, title, field id, target option id, current value
rows=$(jq -r --arg col "$column" '
  .data.repository.issue.projectItems.nodes[]
  | select(.project != null and .project.closed == false)
  | [ .id,
      .project.id,
      (.project.number | tostring),
      .project.title,
      (.project.field.id // ""),
      ((.project.field.options // []) | map(select((.name | ascii_downcase) == ($col | ascii_downcase))) | (.[0].id // "")),
      (.fieldValueByName.name // "(none)") ]
  | @tsv' <<<"$response")

if [[ -z "$rows" ]]; then
  echo "issue #$issue is not on any open project board"
  exit 3
fi

status=0
while IFS=$'\t' read -r item_id project_id number title field_id option_id current; do
  label="board #$number \"$title\""
  if [[ -z "$field_id" ]]; then
    echo "skipped: $label has no single-select field \"$field\""
    status=4
  elif [[ -z "$option_id" ]]; then
    echo "skipped: $label has no \"$column\" option in \"$field\""
    status=4
  elif [[ "${current,,}" == "${column,,}" ]]; then
    echo "already: $label is in \"$current\""
  elif gh project item-edit --id "$item_id" --project-id "$project_id" \
    --field-id "$field_id" --single-select-option-id "$option_id" >/dev/null; then
    echo "moved: $label \"$current\" -> \"$column\""
  else
    echo "failed: $label (gh project item-edit), try: gh auth refresh -s project"
    [[ $status -eq 0 ]] && status=1
  fi
done <<<"$rows"

exit "$status"
