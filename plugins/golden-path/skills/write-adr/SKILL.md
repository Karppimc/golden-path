---
name: write-adr
description: Record an architecture or process decision as a short, numbered record in docs/adr - context, options considered, decision, consequences and sources - and supersede an older record when a decision changes. Use when the user asks to document, record or write up a decision or an ADR, when a plan chose between real alternatives, when a README lists decisions without their reasons, or when a change reverses something decided earlier.
---

# Write ADR

Keep the reasons behind a decision next to the code: what the situation was, what was considered, what was chosen and what follows from it. A record is short, about one screen, and is written when the decision is made, while the reasons are still known.

The process lives in this plugin, two folders up from this skill: `../../references/rules.md` (artefacts in English, changes through an issue and a PR). Resolve it against this skill's base directory.

Never invent a reason, an option or a consequence. Everything in a record must trace to the issue, the pull request, the plan or what the user said; what isn't known is asked, or left out and said so. Never edit the decision of an accepted record: a changed decision is a new record that supersedes the old one.

## 1. Is it a decision worth a record

Write one when the choice was between real alternatives and someone will later ask "why is it like this": a tool or architecture choice, a rule of the process, a security or cost trade-off, a deliberate exception to a standard. Don't write one for something with no alternative, or for an implementation detail the code already explains.

The record goes into the repo the decision is about, through that repo's issue and PR like any change.

## 2. Gather

From what exists, before asking anything:

- the issue (`gh issue view <n> --json title,body,comments`): the problem and the constraints,
- the plan comment `/golden-path:plan-feature` posted: the approach and the rejected alternative,
- the pull request (`gh pr view <n> --json title,body`): what was done, the deliberate deviations,
- the conversation: what the user decided and in their words why.

Then check you can answer all five; ask the user for what is missing, together, in one go:

1. **Context:** what made a decision necessary, and what constrained it.
2. **Options:** which alternatives were really on the table.
3. **Decision:** what was chosen.
4. **Consequences:** what it makes easier and harder, and what would make us revisit it.
5. **Supersedes:** does it replace an earlier record (`docs/adr/README.md` lists them).

## 3. Create

From the repo root: `bash <skill-dir>/scripts/adr.sh new "<title>" [--supersedes <number>] [--date <YYYY-MM-DD>]`

- The title states the decision, not the topic: "The pull request is the human gate", not "Review process".
- `--date` is the day the decision was made, when the record is written later.
- It takes the next free number, creates `docs/adr/NNNN-<slug>.md` with the sections marked `TO-WRITE`, marks a superseded record and links both ways, and rewrites the index `docs/adr/README.md`.

| Exit | Meaning | Do |
|---|---|---|
| 0 | Created | Write the sections |
| 3 | A record with this title exists | Nothing written. Update that record's consequences, or supersede it under a new title |
| 4 | The record to supersede doesn't exist | Check the number in the index |
| 2 | Usage, or not in a git repo | Fix the arguments |

## 4. Write

Replace every `TO-WRITE`:

- **Context:** facts, not the conclusion. Two to five sentences.
- **Options considered:** one short paragraph or bullet per option, with why it was or wasn't chosen. Only options that were considered; one option is fine if that is the truth, then say why no alternative was weighed.
- **Decision:** one or two sentences, present tense, active: "Claude pushes the branch and opens the PR; the owner reviews and merges."
- **Consequences:** both the gains and the costs, and when to revisit.
- **Sources:** links to the issue, PR, plan comment or the place the decision was made.

Then `bash <skill-dir>/scripts/adr.sh check`: it fails while a section is still `TO-WRITE` or the index is out of step.

## 5. Hand over

Commit the record and the index (`docs: record decision NNNN, <title>`), then `/golden-path:create-pr`, or add it to the PR that makes the decision. The owner's review of the record is the check that it says what was actually decided.

## 6. Report

Lead with one line: **Recorded: NNNN. <title>**, or what is still missing.

| Item | Result |
|---|---|
| Record | the file, as a link |
| Supersedes | the old record, or none |
| Sources | what it was based on |
| Asked from the user | what was missing and their answer |

End with **Not verified:** anything in the record that rests on memory rather than a linked source, and the next step: the owner reads the record in the PR.
