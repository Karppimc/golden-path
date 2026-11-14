---
name: create-pr
description: Open a pull request for the current branch the golden-path way - title and body per branching.md, a Closes link to the issue, reviewers from CODEOWNERS, and the issue's board card moved to Review. Use when the user asks to open, create, raise or submit a PR, send the branch for review, or after a review skill gives "ready for PR".
---

# Create PR

Open a pull request for the current branch, link its issue, make sure a reviewer is requested and move the issue's card to **Review**. This is the only sanctioned way to open a PR in our repos (see `rules.md`).

The process lives in this plugin, two folders up from this skill: `../../references/branching.md` (title, body, approvals) and `../../references/board.md` (columns). Resolve them against this skill's base directory and read both before drafting.

Never push to `main`, never force push, never merge, and never open the PR as a draft unless the user asks (GitHub does not request CODEOWNERS on drafts). The human gate is the PR itself: the owner reviews it on GitHub and merges it.

## 1. Preflight

1. Branch: `git branch --show-current`. On `main` (or detached HEAD) stop: the work needs a branch first.
2. Issue number and type from the branch name: `feature/<n>-...` → `feat`, `fix/<n>-...` → `fix`. A `chore/<slug>` branch has no number: ask for the issue. If there is no issue at all, ask before creating one; don't open a PR without `Closes #<n>`.
3. `gh auth status`. If `gh` is missing or not logged in, stop and say so.
4. Working tree (`git status --porcelain`), two cases:
   - Changes to tracked files: ask whether to commit them first. Don't commit or stash on your own.
   - Untracked files: they are not in the PR. List them and ask whether any belong to it (a new file that was never `git add`ed is an easy way to ship half a change). Files clearly unrelated to the issue don't block.
5. `git fetch -q origin main`, then `git log --oneline origin/main..HEAD`. No commits ahead: stop, nothing to open. If `origin/main` is not an ancestor of `HEAD` (`git merge-base --is-ancestor origin/main HEAD`), mention that the branch is behind; don't rebase unasked.
6. Existing PR: `gh pr list --head <branch> --state open --json number,url`. If one exists, don't open another: show it and continue from step 6 (reviewers and board) for that PR.

## 2. Review gate

`rules.md` says to run the matching review skill first and fix blocking findings.

- Changed files: `git diff --name-only origin/main...HEAD`.
- Run the matching review skill for each language changed, if it hasn't run on this branch in this session: `.tf` files → `/golden-path:review-terraform`; Ansible files (playbooks, roles, inventory, `requirements.yml` under the `ansible.cfg` directory) → `/golden-path:review-ansible`; Kubernetes manifests, Kustomize, Argo CD apps, Helm values or Kyverno policies → `/golden-path:review-kubernetes`; in the golden-path repo, any change under `plugins/` → `/golden-path:update-golden-path`.
- Verdict **fix before PR**: stop and show the findings. Continue only if the user explicitly says so, and then list the unfixed findings under "Deliberate deviations".
- No review skill exists yet for the language: say so and note it under "How it was tested".

## 3. Read the issue

`gh issue view <n> --json number,title,body,labels,state,url`. If it's closed or doesn't exist, ask before going on. The issue's spec is the source of truth: compare its acceptance criteria with the commits and the diff (`git diff --stat origin/main...HEAD`, then the diff itself as needed).

## 4. Draft title and body

Title: `<type>: <summary> (#<n>)` per `branching.md`.

- `<type>` from the commits' Conventional Commit types (`feat` wins over `fix`, `fix` over the rest); fall back to the branch prefix.
- `<summary>` in imperative mood, lowercase start, no trailing period, whole title at most 72 characters.

Body, in English, with exactly these sections:

```markdown
## Summary
<one or two sentences: what changes and why, in terms of the issue>

## Changes
- <one bullet per meaningful change, grouped by area; name files or modules>

## How it was tested
- <commands actually run in this session and their result: fmt/validate/tflint, plan, ansible-lint, kubectl diff, review skill verdict>

## Deliberate deviations
- <acceptance criteria not met on purpose, things the issue leaves out on purpose, accepted review findings; "None." if there are none>

Closes #<n>
```

Only write test results you actually saw in this session. If nothing was run, say "Not tested:" and why. Never invent plan output.

Before pushing, check your own work: the review gate passed, the tests in "How it was tested" really ran, and every acceptance criterion is met or listed under "Deliberate deviations". Then push and open without waiting; the owner reviews the PR itself. If the user asked to see the draft first, show it and wait.

## 5. Push and open

1. `git push -u origin <branch>`. If it's rejected (non-fast-forward), stop and explain; don't force.
2. Write the body to a temp file outside the repo (`mktemp`) and run `gh pr create --base main --head <branch> --title "<title>" --body-file <file>`. Delete the temp file afterwards.
3. Note the PR number and URL from the output.

## 6. Reviewers

Reviewers come from CODEOWNERS, so GitHub requests them when the PR opens.

1. `gh pr view <pr> --json author,reviewRequests`.
2. At least one requested reviewer who isn't the author: done.
3. None: look for `.github/CODEOWNERS`, `CODEOWNERS` or `docs/CODEOWNERS` on the base branch.
   - **Solo repo** (every owner in CODEOWNERS is the PR author): this is expected. The owner reviews the PR and merges it; the merge is the approval. Don't ask for a reviewer; report "solo repo, owner reviews and merges".
   - Otherwise tell the user why no one was requested (no CODEOWNERS file or no matching pattern). Every PR needs one approval from someone who didn't write it, so ask who to request and run `gh pr edit <pr> --add-reviewer <login>`. Never guess a login. Suggest adding a CODEOWNERS file if there was none.

## 7. Move the card

Run `bash <skill-dir>/../../scripts/board-move.sh <n> Review` (the shared script at the plugin root). It finds every open board the issue is on, sets its `Status` field to `Review` and never adds or removes items.

| Exit | Meaning | Do |
|---|---|---|
| 0 | Moved, or already in Review | Report the lines it printed |
| 1 | gh/API error, usually missing scope | Ask the user to run `gh auth refresh -s project` themselves (it's interactive), then rerun the script |
| 3 | Issue is on no board | Report it; offer to add it with `gh project item-add`, don't do it unasked |
| 4 | Board lacks the `Status` field or `Review` option | Report which board; don't create fields or options |

A failed board move doesn't undo the PR. Report it and carry on.

## 8. Report

Lead with one line: **PR opened: <url>** (or **PR already open: <url>**).

Then:

| Step | Result |
|---|---|
| Title | `<title>` |
| Issue | Closes #<n> |
| Review gate | Verdict of the review skill / no skill for this language |
| Reviewers | Requested logins, or what's missing |
| Board | Moved to Review / already there / not done and why |

End with **Not verified:** anything that didn't run (CI is still pending, board move skipped, no tests), and the next step for the owner: review the PR (solo repo: the merge is the approval), wait for green CI and squash merge. To skip the wait, the owner can turn on auto-merge themselves: `gh pr merge <pr> --auto --squash` or "Enable auto-merge" on the PR, and GitHub merges once CI and the rules pass. Never run that command yourself. After the merge, run `/golden-path:cleanup-merged-branch` to move the card to Done.
