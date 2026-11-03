---
name: cleanup-merged-branch
description: Tidy up after a pull request is merged - check the PR really merged, switch to an up-to-date main, delete the branch locally and on origin, make sure the issue is closed and move its card to Done. Use when the user says the PR is merged, asks to clean up, delete the branch, or finish an issue.
---

# Cleanup merged branch

Finish an issue after its PR is merged: delete the branch, update `main` and move the card to **Done**. This is the last step of the flow `pick-issue` → review → `create-pr` → merge → cleanup.

The process lives in this plugin, two folders up from this skill: `../../references/branching.md` and `../../references/board.md`. Resolve them against this skill's base directory.

Deleting a branch can lose work, so this skill only deletes what GitHub says is merged and what has no commits beyond the merged PR. It never merges, never force pushes and never touches `main` except to fast-forward it.

## 1. Which branch

- The user named a branch or PR: use it.
- Otherwise the current branch (`git branch --show-current`).
- On `main` with nothing named: list local branches whose PR is merged (`gh pr list --state merged --json headRefName,number` against `git branch --format='%(refname:short)'`) and ask which to clean up.

`gh auth status` first. If `gh` is missing or not logged in, stop and say so.

## 2. Check the PR merged

`gh pr list --head <branch> --state all --json number,state,mergedAt,headRefOid,url,closingIssuesReferences`.

- No PR, or state is `OPEN` or `CLOSED` without `mergedAt`: stop. Say what state it's in; nothing is deleted.
- Merged: note the PR number, `headRefOid` and the linked issues.

Then check for work that didn't make it into the PR. We squash merge, so `git branch -d` can't tell; compare commits instead:

- `git rev-parse <branch>` equal to `headRefOid`, or `git merge-base --is-ancestor <branch> <headRefOid>`: safe.
- Local branch has commits the PR doesn't (`git log --oneline <headRefOid>..<branch>`): stop and show them. They would be lost. Ask whether to keep the branch or move them to a new one.
- `headRefOid` not available locally: `git fetch -q origin` first; still missing means the remote branch is already gone, so fall back to `git log --oneline origin/main..<branch>` and show it to the user before deleting.

## 3. Confirm

Show one line and ask for a yes:

`Delete <branch> locally and on origin? PR #<pr> merged <mergedAt>, no unmerged commits.`

## 4. Switch and delete

1. Uncommitted changes (`git status --porcelain`): stop and ask; switching would carry them to `main`.
2. `git switch main`, then `git pull --ff-only origin main`. If it can't fast-forward, stop and explain; local `main` has commits it shouldn't.
3. `git branch -D <branch>` (capital D is needed after a squash merge; step 2 already checked nothing is lost).
4. Remote: if `git ls-remote --exit-code --heads origin <branch>` finds it, `git push origin --delete <branch>`. GitHub may already have deleted it on merge; then there's nothing to do.
5. `git fetch --prune -q origin`.

## 5. Close out the issue

For each issue in `closingIssuesReferences` (or the number in the branch name if the list is empty):

1. `gh issue view <n> --json state`. Open after the merge means the PR body lacked `Closes #<n>`: ask whether to close it with `gh issue close <n> --comment "Done in #<pr>"`.
2. Run `bash <skill-dir>/../../scripts/board-move.sh <n> Done`. The board's own "item closed" automation may have moved it already; the script then prints `already`.

| Exit | Meaning | Do |
|---|---|---|
| 0 | Moved, or already in Done | Report the lines it printed |
| 1 | gh/API error, usually missing scope | Ask the user to run `gh auth refresh -s project` themselves, then rerun |
| 3 | Issue is on no board | Report it; nothing to move |
| 4 | Board lacks the `Status` field or `Done` option | Report which board |

## 6. Report

Lead with one line: **Cleaned up <branch>** or why it stopped.

| Step | Result |
|---|---|
| PR | #<pr> merged <date> |
| Local branch | Deleted / kept and why |
| Remote branch | Deleted / already gone |
| `main` | Fast-forwarded to `<short sha>` |
| Issue | #<n> closed |
| Board | Moved to Done / already there / not done and why |

End with **Not verified:** anything that didn't run, and offer the next step: other local branches whose PRs are merged (list them, don't delete unasked), or `/golden-path:pick-issue` for the next issue.
