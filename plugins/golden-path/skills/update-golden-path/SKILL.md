---
name: update-golden-path
description: Get a change to the golden-path plugin itself ready to ship - bump the version in plugin.json (patch, minor or major), keep the README skills table, skill count, tree and rules word budget in sync, and run what CI runs (JSON, shellcheck, claude plugin validate) locally. Use in the golden-path repo when a skill, rule, reference, hook or script changed, before create-pr there, or when the user asks to bump, release or ship the plugin.
---

# Update golden-path

Make a change to this plugin shippable: right version bump, README in sync, CI green before it runs. Installed copies only update when `version` goes up, so a missed bump means nobody gets the change.

Only in the golden-path repo (its `.claude-plugin/marketplace.json` is named `golden-path`). Anywhere else, stop and say so.

## 1. Check

`git fetch -q origin main`, then `bash <skill-dir>/scripts/plugin-check.sh`. It compares the branch (committed and uncommitted) with `origin/main`:

- files changed under `plugins/golden-path/`, skills added or removed,
- the version against the base, with a suggested level,
- README: skills table rows against skill folders, the `**N skills · ...**` line, the rules word budget (`rules.md` within 15% of the `~N words` in the tree), the tree showing `hooks/`, `skills/`, `scripts/`, `references/`,
- what CI runs: JSON well-formed, shellcheck on every plugin script, `claude plugin validate` for the marketplace and the plugin.

Exit 0: nothing to fix, go to step 4. Exit 10: the `FIX:` lines say what. Exit 2: not the golden-path repo.

## 2. Version

Semver from the base version, never from a version already bumped on this branch:

| Change | Level |
|---|---|
| Fix, wording, reference or script change that keeps behaviour | patch |
| New skill, new rule, new behaviour that is backwards compatible | minor |
| Removed or renamed skill, a rule that makes existing work non-compliant | major: ask first |

The script suggests patch, minor (skill added) or major (skill removed or renamed). Unsure, or the suggestion is major: ask. Then `bash <skill-dir>/scripts/plugin-check.sh bump <level>`. It edits only the version line.

## 3. README

Fix what the check reported, in the house style:

- **Skills table:** one row per skill, `` `/golden-path:<name>` `` and one sentence on what it does, in the order of the usual flow (onboarding, pick, review, deliver, upkeep).
- **`**N skills · ...**`:** the number of skill folders.
- **Usual flow** line: add the skill if it is a step in the flow.
- **Tree:** a new top-level folder under the plugin gets a line with a comment.
- **Rules budget:** if `rules.md` grew past it, shorten the rules first. Raise the budget only on purpose, and say so in the PR.

Rerun the check until it exits 0. Anything it lists under "Not run" goes into the PR's "How it was tested".

## 4. Hand over

- Commit with the rest of the change, then `/golden-path:create-pr`. Put the version step (`0.7.0 → 0.8.0`) in the PR's Changes.
- In the report, tell the user how to get the new version after the merge:
  ```bash
  claude plugin marketplace update golden-path
  claude plugin update golden-path@golden-path
  ```
  then start a new Claude Code session; plugins load at session start.

## 5. Report

Lead with one line: **Ready to ship: <old> → <new>** or what is still open.

| Check | Result |
|---|---|
| Version | old → new (level, why) |
| Skills table and count | ok / fixed |
| Rules budget | words / budget |
| JSON | ok |
| shellcheck | ok / Not run |
| claude plugin validate | ok / Not run |

End with **Not verified:** what didn't run locally (CI will run it on the PR).
