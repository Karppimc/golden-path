# 0001. The pull request is the human gate

- Status: Accepted
- Date: 2026-11-03

## Context

The golden path says Claude does the work and a human owns the result: every pull request needs an approval from someone who did not write it. This repo and homelab-platform have one maintainer. Claude pushes with the owner's GitHub account, and GitHub does not let an author approve their own pull request, so a required approval can never be given here. The owner still wanted to check Claude's work before it reaches `main`.

## Options considered

- **Require one approval and let the owner bypass it as admin.** Rejected: every merge would be a bypass, so the rule would never actually hold and the bypasses would only be noise.
- **The owner reviews the diff locally before anything is pushed.** This was the first rule, shipped in #1 after the owner said they would check Claude's work before it was pushed anywhere. It was replaced the same day, when the owner asked for the review to happen on the pull request instead: Claude picks an item, implements, tests and pushes it, and the owner reads the pull request and merges.
- **Review on the pull request, with the owner's merge as the approval.** Chosen.

## Decision

Claude pushes the feature branch and opens the pull request without waiting for a local review. The owner reviews the pull request on GitHub and merges it; in a repo with one maintainer that merge is the approval. Claude never pushes to `main`, force pushes, merges, or turns on auto-merge.

## Consequences

- Work no longer stops to wait for a review inside the session, and the review leaves a record on the pull request. Review comments are handled there (`review-comments`).
- The ruleset on `main` enforces what it can: a pull request, a green `validate` check and resolved conversations, squash merge only, no bypass for anyone, and zero required approvals in a solo repo (#15).
- Nothing technical makes the owner read a pull request before merging it. In a solo repo the gate is a convention.
- Unreviewed work is visible on a pushed branch before the review, and both repos are public.
- Auto-merge was added later as the owner's one-click merge; turning it on is the owner's action, the same as merging (#33).
- Revisit when a second person joins a repo: add them to CODEOWNERS and raise the ruleset to one required approval, as `references/branching.md` says.

## Sources

- Issue [#3](https://github.com/Karppimc/golden-path/issues/3) and pull request [#11](https://github.com/Karppimc/golden-path/pull/11): the gate moves from before the push to the pull request.
- Pull request [#1](https://github.com/Karppimc/golden-path/pull/1): the first rule, review before push, and the solo-repo exception.
- Issue [#15](https://github.com/Karppimc/golden-path/issues/15) and pull request [#21](https://github.com/Karppimc/golden-path/pull/21): the ruleset with zero approvals in a solo repo.
- Issue [#33](https://github.com/Karppimc/golden-path/issues/33) and pull request [#35](https://github.com/Karppimc/golden-path/pull/35): auto-merge as the owner's action.
- `plugins/golden-path/references/rules.md` and `branching.md`: the rules as they stand.
- The admin-bypass option was discussed and rejected between the owner and Claude on 2026-11-03, before #1; that discussion is not recorded in an issue.
