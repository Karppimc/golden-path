#!/usr/bin/env bash
# Read-only audit of repos against the golden-path baseline.
# Usage: repo-audit.sh [<owner/repo> ...]   audit the named repos (default: the current folder's repo)
#        repo-audit.sh --board              audit every repo linked to the boards the current repo is on
#
# Per repo it prints PASS / FAIL / N/A lines, each FAIL with what it was based on and the skill
# that fixes it. Changes nothing: GitHub is only read, and files are checked in a temporary
# shallow clone that is removed at the end.
#
# Exit codes: 0 every check passed, 1 gh / API error, 2 usage or missing tool, 10 at least one FAIL
set -uo pipefail

usage() { echo "usage: repo-audit.sh [<owner/repo> ...] | --board" >&2; exit 2; }
for tool in gh jq git; do
  command -v "$tool" >/dev/null 2>&1 || { echo "missing tool: $tool" >&2; exit 2; }
done

here=$(cd "$(dirname "$0")" && pwd)
plugin=$(cd "$here/../../.." && pwd)
policy="$plugin/skills/setup-branch-policy/scripts/branch-policy.sh"

repos=()
board=0
for a in "$@"; do
  case "$a" in
    --board) board=1 ;;
    -*) usage ;;
    */*) repos+=("$a") ;;
    *) usage ;;
  esac
done

# shellcheck disable=SC2016  # $vars below are GraphQL variables, not shell
projects_query='
query($owner: String!, $repo: String!) {
  repository(owner: $owner, name: $repo) {
    projectsV2(first: 20) {
      nodes {
        number title closed
        owner { ... on User { login } ... on Organization { login } }
        repositories(first: 50) { nodes { nameWithOwner } }
      }
    }
  }
}'
projects_of() {  # projects_of <owner/repo> -> JSON
  gh api graphql -f query="$projects_query" -f owner="${1%/*}" -f repo="${1#*/}" 2>/dev/null
}

if [ ${#repos[@]} -eq 0 ]; then
  current=$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null) || { echo "not in a GitHub repo; name one: repo-audit.sh <owner/repo>" >&2; exit 2; }
  if [ $board -eq 1 ]; then
    mapfile -t repos < <(projects_of "$current" | jq -r '.data.repository.projectsV2.nodes[] | select(.closed | not) | .repositories.nodes[].nameWithOwner' | sort -u)
    [ ${#repos[@]} -gt 0 ] || { echo "$current is on no open board; nothing to audit with --board" >&2; exit 2; }
  else
    repos=("$current")
  fi
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
any_fail=0

for repo in "${repos[@]}"; do
  pass=0; fail=0; na=0
  ok()   { printf 'PASS  %s\n' "$1"; pass=$((pass + 1)); }
  bad()  { printf 'FAIL  %s  -> %s\n' "$1" "$2"; fail=$((fail + 1)); }
  skip() { printf 'N/A   %s\n' "$1"; na=$((na + 1)); }

  if ! meta=$(gh api "repos/$repo" 2>/dev/null); then
    echo "##### $repo"; echo "can't read the repo (does it exist, is gh logged in?)"; any_fail=1; echo; continue
  fi
  owner=$(jq -r .owner.login <<<"$meta")
  default=$(jq -r .default_branch <<<"$meta")
  clone="$tmp/$(tr '/' '_' <<<"$repo")"
  if ! git clone -q --depth 1 "$(jq -r .clone_url <<<"$meta")" "$clone" 2>/dev/null \
     && ! gh repo clone "$repo" "$clone" -- -q --depth 1 2>/dev/null; then
    echo "##### $repo"; echo "can't clone the repo"; any_fail=1; echo; continue
  fi
  files() { git -C "$clone" ls-files "$@"; }

  stacks=()
  [ -n "$(files '*.tf' | head -1)" ] && stacks+=(terraform)
  [ -n "$(files 'ansible.cfg' '*/ansible.cfg' | head -1)" ] && stacks+=(ansible)
  if files '*.yaml' '*.yml' | grep -vE '^\.github/' | while read -r f; do
       grep -qE '^apiVersion:' "$clone/$f" && grep -qE '^kind:' "$clone/$f" && echo hit && break
     done | grep -q hit; then stacks+=(kubernetes); fi

  # Solo repo: CODEOWNERS names only the owner, or there is none and the owner is the only collaborator.
  codeowners=""
  for c in .github/CODEOWNERS CODEOWNERS docs/CODEOWNERS; do [ -f "$clone/$c" ] && { codeowners=$c; break; }; done
  solo=1
  if [ -n "$codeowners" ]; then
    others=$(grep -oE '@[A-Za-z0-9_/-]+' "$clone/$codeowners" | tr '[:upper:]' '[:lower:]' | sort -u | grep -vx "@${owner,,}" || true)
    [ -n "$others" ] && solo=0
  else
    [ "$(gh api "repos/$repo/collaborators" --jq 'length' 2>/dev/null || echo 1)" -gt 1 ] && solo=0
  fi
  approvals=$((1 - solo))

  echo "##### $repo (default branch: $default; stacks: ${stacks[*]:-none}; solo: $([ $solo -eq 1 ] && echo yes || echo no))"

  # --- baseline files (init-repo-claude) ---
  if [ -f "$clone/CLAUDE.md" ] || [ -f "$clone/.claude/CLAUDE.md" ]; then ok "CLAUDE.md"; else bad "CLAUDE.md: neither CLAUDE.md nor .claude/CLAUDE.md" "/golden-path:init-repo-claude"; fi
  if [ -n "$codeowners" ]; then ok "CODEOWNERS ($codeowners)"; else bad "CODEOWNERS: none in .github/, root or docs/" "/golden-path:init-repo-claude"; fi
  if jq -e '.enabledPlugins["golden-path@golden-path"] == true' "$clone/.claude/settings.json" >/dev/null 2>&1; then ok ".claude/settings.json enables the plugin"
  else bad ".claude/settings.json: missing, or golden-path@golden-path is not enabled" "/golden-path:init-repo-claude"; fi

  if [ ${#stacks[@]} -eq 0 ]; then
    skip ".gitignore entries (no Terraform, Ansible or Kubernetes in the repo)"
  else
    missing=()
    gi="$clone/.gitignore"
    has() { [ -f "$gi" ] && grep -qF -- "$1" "$gi"; }
    for s in "${stacks[@]}"; do
      case "$s" in
        terraform) has '.tfstate' || missing+=('*.tfstate'); has '.terraform' || missing+=('.terraform/') ;;
        ansible) has '.vault_pass' || missing+=('.vault_pass*') ;;
        kubernetes) has 'kubeconfig' || missing+=('kubeconfig*') ;;
      esac
    done
    if [ ${#missing[@]} -eq 0 ]; then ok ".gitignore entries for ${stacks[*]}"; else bad ".gitignore: missing ${missing[*]}" "/golden-path:init-repo-claude"; fi
  fi

  labels=$(gh label list -R "$repo" --limit 200 --json name --jq '.[].name' 2>/dev/null)
  want=(docs bug "${stacks[@]}")
  missing=()
  for l in "${want[@]}"; do grep -qx "$l" <<<"$labels" || missing+=("$l"); done
  if [ ${#missing[@]} -eq 0 ]; then ok "labels (${want[*]})"; else bad "labels: missing ${missing[*]}" "/golden-path:init-repo-claude"; fi

  projects=$(projects_of "$repo")
  open_projects=$(jq -r '[.data.repository.projectsV2.nodes[] | select(.closed | not)] | length' <<<"$projects" 2>/dev/null || echo 0)
  if [ "$open_projects" -gt 0 ]; then ok "linked to a board ($(jq -r '[.data.repository.projectsV2.nodes[] | select(.closed | not) | "#\(.number) \(.title)"] | join(", ")' <<<"$projects"))"
  else bad "board: the repo is linked to no open project" "/golden-path:init-repo-claude"; fi

  # --- CI and branch policy ---
  checks=$(gh api "repos/$repo/commits/$default/check-runs" --jq '[.check_runs[].name] | unique | join(" ")' 2>/dev/null)
  if grep -qw validate <<<"$checks"; then ok "CI: 'validate' ran on $default (checks: $checks)"
  elif [ -n "$checks" ]; then bad "CI: checks on $default are '$checks', none named validate" "/golden-path:scaffold-ci-workflow"
  else bad "CI: no check runs on $default" "/golden-path:scaffold-ci-workflow"; fi

  plan=$(bash "$policy" plan --repo "$repo" --approvals "$approvals" --check validate 2>&1); rc=$?
  case $rc in
    0) ok "branch policy: ruleset and merge settings match (approvals $approvals)" ;;
    10) bad "branch policy: $(grep -E '^(ruleset|settings): (create|update)' <<<"$plan" | paste -sd ';' - | sed 's/;/; /g')" "/golden-path:setup-branch-policy" ;;
    *) bad "branch policy: plan failed ($(tail -1 <<<"$plan"))" "/golden-path:setup-branch-policy" ;;
  esac

  # --- pinned versions ---
  # Kyverno test fixtures hold bad resources on purpose (a :latest image to prove the policy
  # rejects it), so folders with a kyverno-test.yaml are left out.
  fixtures=$(files '*kyverno-test.yaml' | xargs -r -n1 dirname | sort -u)
  not_fixture() {
    while read -r f; do
      keep=1
      while read -r d; do [ -n "$d" ] && [[ "$f" == "$d"/* ]] && keep=0; done <<<"$fixtures"
      [ $keep -eq 1 ] && echo "$f"
    done
  }
  unpinned=()
  while read -r hit; do [ -n "$hit" ] && unpinned+=("$hit"); done < <(
    cd "$clone" || exit
    files '*.yaml' '*.yml' | not_fixture | xargs -r grep -nE 'image:\s*["'"'"']?[^[:space:]"'"'"']+:latest\b' 2>/dev/null | cut -d: -f1,2 | sed 's/$/ (image :latest)/'
    files '*.tf' | xargs -r grep -nE '^\s*version\s*=\s*"[^~"][^"]*"' 2>/dev/null | cut -d: -f1,2 | sed 's/$/ (provider or module version without ~>)/'
    files '.github/workflows/*' | xargs -r grep -nE 'uses:\s*[^@[:space:]]+@(main|master|latest|HEAD)\b' 2>/dev/null | cut -d: -f1,2 | sed 's/$/ (action from a branch)/'
  )
  if [ ${#unpinned[@]} -eq 0 ]; then ok "versions pinned (images, Terraform versions, actions)"
  else bad "unpinned: $(printf '%s; ' "${unpinned[@]:0:8}")$([ ${#unpinned[@]} -gt 8 ] && echo "and $(( ${#unpinned[@]} - 8 )) more")" "the review skill for that stack"; fi

  # --- work items ---
  orphans=$(gh pr list -R "$repo" --state open --json number,closingIssuesReferences --jq '[.[] | select((.closingIssuesReferences | length) == 0) | "#\(.number)"] | join(" ")' 2>/dev/null)
  if [ -z "$orphans" ]; then ok "open PRs all link an issue"; else bad "open PRs without a linked issue: $orphans" "add 'Closes #<n>' (/golden-path:create-pr)"; fi

  if [ "$open_projects" -gt 0 ]; then
    nostatus=""
    while read -r number powner; do
      [ -n "$number" ] || continue
      found=$(gh project item-list "$number" --owner "$powner" --format json --limit 500 \
        --jq "[.items[] | select(.content.repository == \"$repo\" and (.status == null)) | \"#\(.content.number)\"] | join(\" \")" 2>/dev/null)
      [ -n "$found" ] && nostatus+="$found "
    done < <(jq -r '.data.repository.projectsV2.nodes[] | select(.closed | not) | "\(.number) \(.owner.login)"' <<<"$projects")
    if [ -z "$nostatus" ]; then ok "board cards all have a Status"; else bad "board cards without a Status: $nostatus" "scripts/board-move.sh <n> Todo"; fi
  else
    skip "board cards (no board)"
  fi

  echo "Summary: $pass pass, $fail fail, $na n/a"
  echo
  [ $fail -gt 0 ] && any_fail=1
done

# --- plugin installs, once per run ---
echo "##### Plugin installs on this machine"
source_repo=$(jq -r '.repository // empty' "$plugin/.claude-plugin/plugin.json" | sed -E 's|https://github.com/||; s|\.git$||')
latest=""
[ -n "$source_repo" ] && latest=$(gh api "repos/$source_repo/contents/plugins/golden-path/.claude-plugin/plugin.json" --jq .content 2>/dev/null | base64 -d 2>/dev/null | jq -r .version 2>/dev/null)
installed="$HOME/.claude/plugins/installed_plugins.json"
if [ -z "$latest" ]; then
  echo "N/A   cannot read the latest version from ${source_repo:-the plugin repository}"
elif [ ! -f "$installed" ]; then
  echo "N/A   no $installed"
else
  echo "latest on $source_repo: $latest"
  while IFS=$'\x1f' read -r scope path version; do
    where="$scope$([ -n "$path" ] && echo " ($path)")"
    if [ "$version" = "$latest" ]; then echo "PASS  $where: $version"
    else
      echo "FAIL  $where: $version, latest is $latest  -> claude plugin update golden-path@golden-path --scope $scope$([ "$scope" = project ] && echo " (run in $path)")"
      any_fail=1
    fi
  done < <(jq -r '.plugins["golden-path@golden-path"][]? | [.scope, (.projectPath // ""), .version] | join("\u001f")' "$installed")
fi

[ $any_fail -eq 0 ] && exit 0
exit 10
