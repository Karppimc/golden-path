---
name: audit-repo
description: Check one repo or every repo on the board against the golden-path baseline without changing anything - CLAUDE.md, CODEOWNERS, plugin settings, gitignore, labels, board link, CI check, ruleset and merge settings, pinned versions, PRs without an issue, cards without a status, and stale plugin installs. Use when the user asks to audit, check compliance or drift, asks whether a repo is on the golden path or still set up correctly, or before and after onboarding a repo.
---

# Audit repo

Tell whether a repo still meets the golden-path baseline, and which skill fixes each gap. `init-repo-claude` brings a repo to the baseline once; this shows when it has drifted since.

The baseline lives in this plugin, two folders up from this skill: `../../references/rules.md`, `../../references/branching.md` and `../../references/board.md`. Resolve them against this skill's base directory.

Read-only. This skill changes nothing: not in the repo, not in GitHub settings. Fixing is a separate step with the skill the audit names, after the user says which gaps to close.

## 1. Choose the scope

- A repo the user named: `<owner>/<repo>`, one or several.
- Nothing named: the repo of the current folder.
- "All", "every repo", "the platform": `--board`, which audits every repo linked to the boards the current repo is on. A repo joins that set when `init-repo-claude` links it to the board. Don't audit every repo the owner has: most are outside the platform and would only list failures.

## 2. Run

`bash <skill-dir>/scripts/repo-audit.sh [<owner/repo> ...]` or `bash <skill-dir>/scripts/repo-audit.sh --board`

It reads GitHub and a temporary shallow clone (removed at the end) and prints, per repo, `PASS`, `FAIL` or `N/A` for:

| Check | Fixed by |
|---|---|
| `CLAUDE.md`, CODEOWNERS, `.claude/settings.json` enabling the plugin, `.gitignore` entries for the stacks found, labels, board link | `/golden-path:init-repo-claude` |
| A check named `validate` ran on the default branch | `/golden-path:scaffold-ci-workflow` |
| Ruleset `golden-path: main` and merge settings (approvals 0 in a solo repo) | `/golden-path:setup-branch-policy` |
| Versions pinned: no `:latest` image, Terraform versions with `~>`, no action from a branch | the review skill for that stack |
| Open PRs all link an issue | `/golden-path:create-pr` (`Closes` link) |
| Board cards all have a Status | `scripts/board-move.sh <n> Todo` |

and once per run, every install of the plugin on this machine against the version on the plugin's `main`, with the update command for each stale one.

| Exit | Meaning |
|---|---|
| 0 | Every check passed |
| 10 | At least one FAIL: the lines say what and why |
| 1 | gh / API error |
| 2 | Usage, missing tool, or not in a GitHub repo and none named |

## 3. Weigh the failures

Read each FAIL before reporting it: it says what it was based on. Check it is a real gap and not a false alarm (Kyverno test fixtures are already left out of the image check; a repo may have a good reason, like a deliberate exception). A false alarm in the script is a bug in this skill: say so and offer to file it.

## 4. Report

Lead with one line: **Audit: all repos on the baseline**, or **Audit: N gaps in M repos**.

One table per repo:

| Check | Result | Fix |
|---|---|---|
| each check | Pass / Fail (why) / N/A | the skill or command |

Then the plugin installs (scope, version, latest), **Not verified:** what the audit can't see (whether CODEOWNERS names the right people, whether CLAUDE.md is still accurate, anything inside the cluster), and the next step: offer to run the fixing skill for the gaps the user picks. Don't start fixing unasked.
