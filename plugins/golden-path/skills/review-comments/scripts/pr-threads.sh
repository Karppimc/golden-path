#!/usr/bin/env bash
# Review threads on a pull request: list them, reply to one, resolve one.
# Usage: pr-threads.sh list [<pr>] [--all]      open threads (all with --all), review summaries, PR comments
#        pr-threads.sh reply <thread-id> <body-file>
#        pr-threads.sh resolve <thread-id>
# <pr> defaults to the PR of the current branch.
#
# Exit codes: 0 ok, 1 gh / API error, 2 usage or missing tool, 3 no PR for this branch
set -euo pipefail

usage() { echo "usage: pr-threads.sh list [<pr>] [--all] | reply <thread-id> <body-file> | resolve <thread-id>" >&2; exit 2; }
for tool in gh jq; do
  command -v "$tool" >/dev/null 2>&1 || { echo "missing tool: $tool" >&2; exit 2; }
done

cmd="${1:-}"; shift || true

case "$cmd" in
  list)
    pr=""; all=false
    for a in "$@"; do
      case "$a" in
        --all) all=true ;;
        *[!0-9]*|"") usage ;;
        *) pr="$a" ;;
      esac
    done
    if [ -z "$pr" ]; then
      pr=$(gh pr view --json number --jq .number 2>/dev/null) || { echo "no pull request for branch $(git branch --show-current)" >&2; exit 3; }
    fi
    nwo=$(gh repo view --json nameWithOwner --jq .nameWithOwner) || exit 1
    # shellcheck disable=SC2016  # $vars below are GraphQL variables, not shell
    query='
    query($owner: String!, $repo: String!, $n: Int!) {
      repository(owner: $owner, name: $repo) {
        pullRequest(number: $n) {
          number url state headRefName reviewDecision
          reviewThreads(first: 100) {
            totalCount
            nodes {
              id isResolved isOutdated path line originalLine
              comments(first: 50) { totalCount nodes { author { login } body createdAt url } }
            }
          }
          reviews(first: 50) { totalCount nodes { state author { login } body submittedAt } }
          comments(last: 30) { totalCount nodes { author { login } body createdAt url } }
        }
      }
    }'
    data=$(gh api graphql -f query="$query" -f owner="${nwo%/*}" -f repo="${nwo#*/}" -F n="$pr") || exit 1
    jq -r --argjson all "$all" '
      .data.repository.pullRequest as $p
      | def indent: split("\n") | map("    " + .) | join("\n");
        "PR #\($p.number) \($p.state) \($p.headRefName) \($p.url)",
        "Review decision: \($p.reviewDecision // "none")",
        "Threads: \([$p.reviewThreads.nodes[] | select(.isResolved | not)] | length) open, \([$p.reviewThreads.nodes[] | select(.isResolved)] | length) resolved",
        # No pagination: say so when a list was cut, instead of dropping items silently.
        ( if $p.reviewThreads.totalCount > ($p.reviewThreads.nodes | length)
          then "WARNING: showing \($p.reviewThreads.nodes | length) of \($p.reviewThreads.totalCount) threads; read the rest on GitHub" else empty end ),
        ( $p.reviewThreads.nodes[] | select(.comments.totalCount > (.comments.nodes | length))
          | "WARNING: thread \(.id) shows \(.comments.nodes | length) of \(.comments.totalCount) comments" ),
        ( if $p.reviews.totalCount > ($p.reviews.nodes | length)
          then "WARNING: showing \($p.reviews.nodes | length) of \($p.reviews.totalCount) reviews" else empty end ),
        ( if $p.comments.totalCount > ($p.comments.nodes | length)
          then "WARNING: showing the last \($p.comments.nodes | length) of \($p.comments.totalCount) PR comments" else empty end ),
        "",
        ( $p.reviewThreads.nodes[]
          | select($all or (.isResolved | not))
          | "== thread \(.id) [\(if .isResolved then "resolved" else "open" end)\(if .isOutdated then ", outdated" else "" end)] \(.path):\(.line // .originalLine // "-")",
            ( .comments.nodes[] | "  @\(.author.login // "ghost") \(.createdAt[0:16]):\n\(.body | indent)" ),
            "" ),
        ( [$p.reviews.nodes[] | select(.body != "")] as $r
          | if ($r | length) > 0 then "== review summaries", ($r[] | "  @\(.author.login // "ghost") \(.state) \(.submittedAt[0:16] // ""):\n\(.body | indent)"), "" else empty end ),
        ( $p.comments.nodes as $c
          | if ($c | length) > 0 then "== PR conversation (last \($c | length))", ($c[] | "  @\(.author.login // "ghost") \(.createdAt[0:16]) \(.url):\n\(.body | indent)") else empty end )
    ' <<<"$data"
    ;;
  reply)
    if [ $# -ne 2 ] || [ ! -f "$2" ]; then usage; fi
    # shellcheck disable=SC2016
    gh api graphql -f query='
      mutation($t: ID!, $b: String!) {
        addPullRequestReviewThreadReply(input: {pullRequestReviewThreadId: $t, body: $b}) { comment { url } }
      }' -f t="$1" -F b=@"$2" --jq '"replied: \(.data.addPullRequestReviewThreadReply.comment.url)"'
    ;;
  resolve)
    [ $# -eq 1 ] || usage
    # shellcheck disable=SC2016
    gh api graphql -f query='
      mutation($t: ID!) { resolveReviewThread(input: {threadId: $t}) { thread { id isResolved } } }' \
      -f t="$1" --jq '"resolved: \(.data.resolveReviewThread.thread.id) \(.data.resolveReviewThread.thread.isResolved)"'
    ;;
  *) usage ;;
esac
