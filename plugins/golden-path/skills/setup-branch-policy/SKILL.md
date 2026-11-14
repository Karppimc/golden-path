---
name: setup-branch-policy
description: Create or repair the GitHub ruleset that protects main per branching.md - PR required, approvals (0 in a solo repo), stale reviews dismissed, conversations resolved, CI required, squash only, no force push or deletion - and the repo's merge settings. Use when the user asks to protect main, set up or check branch protection or rulesets, or when init-repo-claude onboards a repo.
---

# Setup branch policy

Bring the repo's default branch in line with `branching.md`: one ruleset named `golden-path: main` and the repo's merge settings. Rerunnable on any repo; a second run changes nothing.

The policy lives in this plugin, two folders up from this skill: `../../references/branching.md`. Resolve it against this skill's base directory and read the "Pull requests" and "GitHub ruleset" sections first.

This changes how everyone can push and merge. Never apply without showing the plan and getting the user's explicit yes. Never delete or edit other rulesets or classic branch protection; report them.

## 1. Preflight

1. `gh auth status`; stop if `gh` is missing or not logged in.
2. Admin rights: `gh api repos/<owner>/<repo> --jq .permissions.admin` must be `true`. Otherwise stop: rulesets need admin.
3. The policy requires a CI check. If the default branch has no check runs yet, stop and suggest adding a lint/validate workflow first.

## 2. Decide the inputs

**Approvals.** Solo repo → 0, otherwise 1 (`branching.md`).

- Read CODEOWNERS from the default branch (`.github/CODEOWNERS`, `CODEOWNERS`, `docs/CODEOWNERS`) with `gh api repos/<owner>/<repo>/contents/<path>`.
- Solo: every owner in it is the repo owner. No CODEOWNERS: solo if `gh api repos/<owner>/<repo>/collaborators --jq '[.[].login]'` is only the owner; suggest adding CODEOWNERS either way.
- Anyone else in CODEOWNERS or as a collaborator → 1. Unsure → ask.

**Required checks.** The check names CI reports on the default branch: `gh api repos/<owner>/<repo>/commits/<default>/check-runs --jq '[.check_runs[].name] | unique'`. One name → use it. Several → show them and ask which are required. A check that never ran on the default branch would block every PR; don't require it.

## 3. Plan

Run `bash <skill-dir>/scripts/branch-policy.sh plan --approvals <n> --check <name> [--check <name>...]`. It works on the repo of the current folder; `--repo <owner/name>` points it at another one.

It compares only what it manages:

- Ruleset `golden-path: main` on `~DEFAULT_BRANCH`, active, no bypass actors: deletion and non-fast-forward blocked; pull request required with `<n>` approvals, stale reviews dismissed on push, review threads resolved, squash merge only; required status checks.
- Repo settings: squash merge only, delete head branches after merge, allow auto-merge (the owner turns it on per PR).

| Exit | Meaning |
|---|---|
| 0 | Nothing to change. Report and stop. |
| 10 | Changes pending; the output shows them. |
| 1 | gh/API error: show it. |
| 2 | Usage or missing tool. |

It also lists other rulesets, extra rules on ours and classic branch protection. Those are never touched.

## 4. Apply

Show the plan output and, in plain words, what changes for the user: direct pushes to `main` stop working, PRs need green `<checks>` and resolved conversations, only squash merge, branches deleted after merge, and the owner can turn on auto-merge for a PR. Ask for a yes.

On yes: `bash <skill-dir>/scripts/branch-policy.sh apply --approvals <n> --check ...`, then run `plan` again. It must exit 0; anything else, report it.

## 5. Report

Lead with one line: **Branch policy: applied**, **already in place** or why it stopped.

| Item | Result |
|---|---|
| Ruleset `golden-path: main` | Created / updated / ok (id) |
| Approvals | 0 (solo repo) / 1 |
| Required checks | names |
| Merge settings | Squash only, delete branches after merge, auto-merge allowed |
| Other rulesets / classic protection | Listed, not touched |

End with **Not verified:** anything not checked (e.g. a required check that hasn't run on a PR yet), and a note that this PR and the next one are the first to run under the policy.
