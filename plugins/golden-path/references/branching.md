# Branching and pull requests

## Branches
- `main` is protected: no direct pushes, no force pushes, PR required.
- Feature work: `feature/<issue>-<short-slug>`, fixes: `fix/<issue>-<short-slug>`, chores: `chore/<short-slug>`.
- Branch from a freshly fetched `origin/main`. Unset the upstream to `main` so a plain `git push` can't reach it.
- Delete the branch after merge (`/golden-path:cleanup-merged-branch`).

## Commits
- Conventional Commits: `feat:`, `fix:`, `chore:`, `docs:`, `refactor:`, `ci:`.
- Subject in imperative mood, max 72 characters. Reference the issue in the body.

## Pull requests
- Title: `<type>: <summary> (#<issue>)`.
- Body sections: Summary, Changes, How it was tested (plan/lint output), Deliberate deviations, `Closes #<issue>`.
- Reviewers come from the repo's `CODEOWNERS`. If no one else is requested, ask for a reviewer by name.
- One approval from someone other than the author; new commits dismiss stale approvals.
- Solo repos: when CODEOWNERS lists only the owner, nobody else can approve. The owner reviews Claude's diff before it is pushed, and the PR body says so under "How it was tested". When a second person joins, add them to CODEOWNERS and raise the ruleset back to 1 approval.
- All conversations resolved and CI green before merge. Squash merge.

## GitHub ruleset for `main` (set by `init-repo-claude`)
- Require a pull request, 1 approval (0 in a solo repo), dismiss stale reviews, require conversation resolution.
- Require status checks: the repo's lint/validate workflow.
- Block force pushes and deletions.
