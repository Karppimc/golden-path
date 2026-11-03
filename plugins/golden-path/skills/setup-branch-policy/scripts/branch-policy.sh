#!/usr/bin/env bash
# Compare or apply the golden-path branch policy for the current repo's default branch.
# The policy is one repository ruleset named "golden-path: main" plus repo merge settings
# (squash only, delete head branches after merge). Other rulesets are listed, never touched.
#
# Usage: branch-policy.sh plan|apply --approvals <n> --check <name> [--check <name>...]
#
# Exit codes:
#   0   plan: nothing to change / apply: applied
#   1   gh / API error
#   2   usage error or missing tool
#   10  plan: changes pending
set -euo pipefail

usage() { echo "usage: branch-policy.sh plan|apply --approvals <n> --check <name> [--check <name>...]" >&2; exit 2; }

mode="${1:-}"; shift || true
[[ "$mode" == plan || "$mode" == apply ]] || usage
approvals=""
checks=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --approvals) approvals="${2:-}"; shift 2 ;;
    --check) checks+=("${2:-}"); shift 2 ;;
    *) usage ;;
  esac
done
[[ "$approvals" =~ ^[0-9]+$ ]] || usage
[[ ${#checks[@]} -gt 0 ]] || usage
for tool in gh jq diff; do
  command -v "$tool" >/dev/null 2>&1 || { echo "missing tool: $tool" >&2; exit 2; }
done

repo=$(gh repo view --json nameWithOwner --jq .nameWithOwner) || exit 1
name="golden-path: main"

checks_json=$(printf '%s\n' "${checks[@]}" | jq -R '{context: .}' | jq -s .)
desired=$(jq -n --arg name "$name" --argjson n "$approvals" --argjson checks "$checks_json" '{
  name: $name,
  target: "branch",
  enforcement: "active",
  bypass_actors: [],
  conditions: { ref_name: { include: ["~DEFAULT_BRANCH"], exclude: [] } },
  rules: [
    { type: "deletion" },
    { type: "non_fast_forward" },
    { type: "pull_request", parameters: {
        required_approving_review_count: $n,
        dismiss_stale_reviews_on_push: true,
        require_code_owner_review: false,
        require_last_push_approval: false,
        required_review_thread_resolution: true,
        allowed_merge_methods: ["squash"] } },
    { type: "required_status_checks", parameters: {
        strict_required_status_checks_policy: false,
        required_status_checks: $checks } }
  ]
}')
desired_settings='{"allow_squash_merge":true,"allow_merge_commit":false,"allow_rebase_merge":false,"delete_branch_on_merge":true}'

# Project the current ruleset onto the keys we manage, so GitHub's extra fields and defaults don't show as changes.
project='
  def proj($d):
    . as $c
    | if ($d|type) == "object" then
        ($c // {}) as $cc | reduce ($d|keys[]) as $k ({}; .[$k] = ($cc[$k] | proj($d[$k])))
      elif ($d|type) == "array" and ($d|length) > 0 and ($d[0]|type) == "object" then
        [ ($c // [])[] | proj($d[0]) ]
      else $c end;
  . as $cur
  | $desired
  | . as $d
  | ($d | del(.rules)) as $top
  | ($cur | proj($top))
    + { rules: [ $d.rules[] as $r
                 | ($cur.rules // [] | map(select(.type == $r.type)) | .[0])
                 | if . == null then null else proj($r) end ] }'

rulesets=$(gh api "repos/$repo/rulesets" --paginate) || exit 1
id=$(jq -r --arg name "$name" '.[] | select(.name == $name) | .id' <<<"$rulesets" | head -1)
others=$(jq -r --arg name "$name" '.[] | select(.name != $name) | "\(.name) (\(.enforcement))"' <<<"$rulesets")

if [[ -n "$id" ]]; then
  current=$(gh api "repos/$repo/rulesets/$id") || exit 1
  projected=$(jq --argjson desired "$desired" "$project" <<<"$current")
  extra=$(jq -r --argjson desired "$desired" '[.rules[].type] - [$desired.rules[].type] | .[]' <<<"$current")
else
  projected=""
  extra=""
fi

settings_now=$(gh api "repos/$repo" --jq '{allow_squash_merge, allow_merge_commit, allow_rebase_merge, delete_branch_on_merge}') || exit 1

pending=0
echo "repo: $repo"
if [[ -z "$id" ]]; then
  echo "ruleset: create \"$name\""
  jq . <<<"$desired" | sed 's/^/  + /'
  pending=1
elif [[ "$(jq -S . <<<"$projected")" != "$(jq -S . <<<"$desired")" ]]; then
  echo "ruleset: update \"$name\" (id $id)"
  diff <(jq -S . <<<"$projected") <(jq -S . <<<"$desired") | sed 's/^/  /' || true
  pending=1
else
  echo "ruleset: ok \"$name\" (id $id)"
fi
[[ -n "$extra" ]] && echo "ruleset: extra rules kept as they are: $(tr '\n' ' ' <<<"$extra")"
[[ -n "$others" ]] && echo "other rulesets (not touched): $(tr '\n' ';' <<<"$others")"
if gh api "repos/$repo/branches/$(gh repo view --json defaultBranchRef --jq .defaultBranchRef.name)/protection" >/dev/null 2>&1; then
  echo "classic branch protection: present (not touched; consider removing it in favour of the ruleset)"
fi

if [[ "$(jq -S . <<<"$settings_now")" != "$(jq -S . <<<"$desired_settings")" ]]; then
  echo "settings: update"
  diff <(jq -S . <<<"$settings_now") <(jq -S . <<<"$desired_settings") | sed 's/^/  /' || true
  pending=1
else
  echo "settings: ok"
fi

if [[ "$mode" == plan ]]; then
  [[ $pending -eq 1 ]] && exit 10
  exit 0
fi

if [[ -z "$id" ]]; then
  gh api -X POST "repos/$repo/rulesets" --input - <<<"$desired" --jq '"applied: created ruleset \(.id)"'
elif [[ "$(jq -S . <<<"$projected")" != "$(jq -S . <<<"$desired")" ]]; then
  # Keep rules we don't manage: merge ours over the current list by type.
  body=$(jq --argjson desired "$desired" '
    $desired + { rules: ( [ .rules[] | select(.type as $t | [$desired.rules[].type] | index($t) | not) ] + $desired.rules ) }' <<<"$current")
  gh api -X PUT "repos/$repo/rulesets/$id" --input - <<<"$body" --jq '"applied: updated ruleset \(.id)"'
fi
if [[ "$(jq -S . <<<"$settings_now")" != "$(jq -S . <<<"$desired_settings")" ]]; then
  gh api -X PATCH "repos/$repo" --input - <<<"$desired_settings" --jq '"applied: settings squash=\(.allow_squash_merge) merge=\(.allow_merge_commit) rebase=\(.allow_rebase_merge) delete_branch_on_merge=\(.delete_branch_on_merge)"'
fi
