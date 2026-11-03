---
name: pick-issue
description: Start work on a GitHub issue the golden-path way - read the spec, assign it, create the branch per branching.md, move the card to In Progress and plan the work against the coding standards. Use when the user says start on, pick up, take or work on issue #n, or asks what to work on next.
---

# Pick issue

Start work on an issue: read its spec, create the branch, move its card to **In Progress** and plan (or do) the work. The issue's spec is the source of truth for everything after this.

The process lives in this plugin, two folders up from this skill: `../../references/branching.md` (branch names, commits), `../../references/board.md` (columns, what an issue must have) and `../../references/coding-standards/`. Resolve them against this skill's base directory.

Nothing in this skill pushes. The branch stays local until `/golden-path:create-pr` pushes it and opens the PR for the owner's review.

## 1. Which issue

- The user named one (`#12`, `12`, an issue URL): use it.
- None named: list candidates with `gh issue list --assignee @me --state open` and the open issues on the board's **Todo** column (`gh issue list --state open --label <label>` if a label was given). Show a short list and ask which one. Don't pick for the user.

`gh auth status` first. If `gh` is missing or not logged in, stop and say so.

## 2. Read the spec

`gh issue view <n> --json number,title,body,labels,state,assignees,url`.

- Closed: stop and ask.
- Check what `board.md` says every issue has: a clear title, acceptance criteria as a checklist, a label (`terraform`, `ansible`, `kubernetes`, `docs`, `bug`). Anything missing: say what and ask whether to go on anyway or fix the issue first. Don't edit the issue unasked.
- Note what the spec leaves out on purpose. Those become `[Observation]`s in reviews and "Deliberate deviations" in the PR, not defects.

## 3. Assign

- Unassigned: `gh issue edit <n> --add-assignee @me`.
- Already yours: say so, nothing to do.
- Someone else's: stop and ask before taking it over.

## 4. Branch

Check the working tree first. Uncommitted changes (`git status --porcelain`) would come along to the new branch: ask whether to commit, stash or leave them. Don't decide for the user.

Name per `branching.md`:

- `fix/<n>-<slug>` when the issue has the `bug` label, otherwise `feature/<n>-<slug>`.
- `<slug>`: from the title, lowercase, ASCII, words joined with `-`, filler words dropped, at most about 40 characters. Example: "Add a Proxmox VM module for k3s nodes" → `feature/12-proxmox-vm-module-k3s`.

Existing branch for this issue (`git branch -a --list '*/<n>-*'`): don't create a second one. Offer to switch to it, and continue from step 5.

Otherwise:

1. `git fetch -q origin main`
2. `git switch --no-track -c <branch> origin/main`. `--no-track` leaves no upstream, so a plain `git push` can't reach `main`. Check with `git rev-parse --abbrev-ref @{u}`: it must fail.

## 5. Move the card

Run `bash <skill-dir>/../../scripts/board-move.sh <n> "In Progress"`.

| Exit | Meaning | Do |
|---|---|---|
| 0 | Moved, or already in In Progress | Report the lines it printed |
| 1 | gh/API error, usually missing scope | Ask the user to run `gh auth refresh -s project` themselves (it's interactive), then rerun |
| 3 | Issue is on no board | Report it; offer to add it with `gh project item-add`, don't do it unasked |
| 4 | Board lacks the `Status` field or `In Progress` option | Report which board; don't create fields or options |

A failed board move doesn't stop the work. Report it and carry on.

## 6. Plan

1. Read `general.md` plus the standard for the issue's label: `terraform.md`, `ansible.md` or `kubernetes.md`. For `docs` and `bug` issues, pick by the files involved.
2. Read the code the issue touches, enough to know where the change goes.
3. Turn the acceptance criteria into a todo list, one item per criterion, plus anything the standard requires (README for a new module, variable validation...).
4. Short plan: which files change or are created, in what order, and anything in the spec that is ambiguous. Ask about ambiguities now rather than guessing.

If the user only asked to pick up the issue, stop here and show the plan. If they asked to start or do the work, go on.

## 7. Do the work

- Follow the plan and the standards. Stay inside the issue's scope; something extra you notice goes in the report as a suggestion for a new issue.
- Safety rules from `rules.md` apply: `plan`, `validate`, lint, `--check --diff` and `kubectl diff` are fine; `apply`, `destroy`, real playbook runs and `kubectl apply/delete` need the user's explicit yes in this session.
- When done, run the matching review skill (`/golden-path:review-terraform` for `.tf` changes) and fix Blocking and Should fix findings.
- Don't commit unasked. Propose the commit: Conventional Commit subject in imperative mood (max 72 characters), issue referenced in the body (`Refs #<n>`), and ask.

## 8. Report

Lead with one line: what state the work is in (**Picked up #<n>, plan ready** / **#<n> implemented, review: ready for PR**).

Then **Where things are:**

- **Branch:** `<branch>`, based on `origin/main`, no upstream.
- **Issue #<n>:** assigned to you, card in In Progress (or why not).
- **Not committed yet:** the changed files as links, if any.

Then the review verdict and findings if step 7 ran, **Not verified:** what you couldn't check, and one next step: answer the open questions, commit, or run `/golden-path:create-pr`.
