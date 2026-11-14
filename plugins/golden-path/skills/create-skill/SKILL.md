---
name: create-skill
description: Add a new skill to the golden-path plugin in the house style - a skeleton with frontmatter, numbered steps and a report, deterministic work in a script, checked by the skill linter, then the version bump and README row. Use when the user asks to create, add or write a new skill or to turn a repeated procedure into a command, or when the same manual steps have been done a third time.
---

# Create skill

Turn a procedure the team repeats into a skill that reads and behaves like the others. A skill is instructions for Claude, so it is judged by whether a fresh session can follow it without this conversation.

Only in the golden-path repo. The repo's `CLAUDE.md` and the existing skills are the reference for the house style; read two skills close to the new one before writing (a review skill for a review, a scaffold for a scaffold).

Never copy another skill's steps instead of calling it: point to `/golden-path:<other skill>` so there is one place to fix. Never overwrite an existing skill; changing one is ordinary work on its files.

## 0. Start from an issue

The work needs an issue and its branch (`rules.md`). A new skill is a larger issue: if the plan isn't agreed yet, go through `/golden-path:plan-feature` first.

## 1. Pin down the procedure

Ask, or take from the issue, and don't write before these are clear:

- **What it does:** the outcome in one sentence, and the steps a person does by hand today.
- **When it triggers:** the phrases a user would say and the situations where Claude should pick it without being asked.
- **What it must never do**, and what needs an explicit yes (anything that pushes, deletes, applies, changes settings or is visible to others).
- **Which parts are deterministic:** same input, same output. Those go into a script; judgement stays in the prose.
- **Where it stops and hands over:** which existing skills come before and after it.

## 2. Scaffold

`bash <skill-dir>/scripts/skill-new.sh <name> [--script <file.sh>]`

It creates `skills/<name>/SKILL.md` with the standard sections, and the script with the standard header when asked. Exit 3: the skill exists, nothing written. Every part to write is marked `FILL:`.

## 3. Write

Replace every `FILL:`. The house style:

- **Description:** one line. First what it does, then `Use when ...` with the trigger phrases and situations. No ` #` and no `: ` (YAML cuts the line there and the triggers are lost).
- **Opening:** what the procedure achieves; where its rules live (`../../references/...`, resolved against the skill's base directory); the safety line.
- **Steps:** numbered `## 1.`, imperative, each saying when to stop or ask. Tables for exit codes and for "situation → what to do".
- **Scripts:** header with what it does, `# Usage:` and exit codes; `set -euo pipefail` (or `-uo` when it must keep going and report); a missing tool is reported, never installed; never overwrite or delete without the check being in the script; prints what a person needs to read, not raw API output. A script more than one skill needs goes in the plugin's `scripts/`.
- **Report:** last step. One-line verdict first, a table, then **Not verified:** and one next step.
- Write for a reader with no context: a session that only has this file. Say why a rule exists when it isn't obvious.

## 4. Check

1. `bash <skill-dir>/scripts/skill-lint.sh <plugin>/skills/<name>`: name matches the folder, description intact with triggers, numbered steps ending in a Report with "Not verified", every script, skill and reference it mentions exists, no `FILL:` left. Exit 10: fix the lines it prints.
2. Run the script for real: the normal case, each refusal and each exit code. Use a temp folder or a worktree for anything that writes.
3. Follow the skill once as written, on a real case, and fix what was unclear. What couldn't be tried goes under "Not tested" in the PR.

## 5. Ship

Run `/golden-path:update-golden-path`: it bumps the version (minor for a new skill), adds the README row and count, and runs what CI runs, including the lint for every skill. Then `/golden-path:create-pr`.

## 6. Report

Lead with one line: **Skill `<name>` ready for PR**, or what is open.

| Item | Result |
|---|---|
| Procedure and triggers | one line each |
| Script | name and what it does, or none |
| skill-lint | ok |
| Tried for real | the cases run and their results |
| Version | old → new |

End with **Not verified:** what wasn't tried for real, and the next step: review the PR.
