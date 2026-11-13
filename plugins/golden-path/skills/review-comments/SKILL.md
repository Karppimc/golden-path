---
name: review-comments
description: Work through the review comments on the current branch's pull request - read every open thread, fix what is asked in new commits, answer questions, explain disagreements, push, reply per thread and resolve the threads that were fixed. Use when the user says the PR has comments or review feedback, asks to address, answer or resolve review comments, or the PR is blocked on unresolved conversations.
---

# Review comments

Handle the review on an open PR: every open thread gets a fix or a reply, and the owner can see what happened to each one. The ruleset requires resolved conversations before merge, so this is often what stands between a PR and its merge.

The process lives in this plugin, two folders up from this skill: `../../references/branching.md` and `../../references/rules.md`. Resolve them against this skill's base directory.

Never resolve a thread without a fix or a reply in it. Never force push or rewrite the PR's history: fixes go in new commits. Never merge.

## 1. Read the review

1. `gh auth status`; stop if `gh` is missing or not logged in.
2. The PR: the current branch's (`bash <skill-dir>/scripts/pr-threads.sh list`), or the number the user gave (`list <pr>`). Exit 3: no PR for this branch, stop and say so. A merged or closed PR: stop.
3. Check out the PR's branch if needed and `git pull --ff-only`, so fixes go on top of what was reviewed.
4. The output has open threads (id, file:line, outdated or not, every comment), review summaries and the PR conversation. Read the issue too (`Closes #<n>`): it decides what is in scope.

No open threads, no review summary or comment waiting for an answer: say so and stop.

## 2. Decide per thread

Read the code each thread points at (for an outdated thread, the current version of that code). Then put every thread in one group:

- **Fix:** a change request or a defect you agree with. You will change the code.
- **Answer:** a question. You will reply; change nothing unless the answer shows something is wrong.
- **Disagree:** a request that conflicts with the issue's spec, a standard, or would widen the scope. You will reply with the reason and, if it is real work, offer a new issue.

Show the plan as a table (thread, file:line, one-line summary, group, what you'll do) before changing anything. If a comment is ambiguous, ask instead of guessing.

## 3. Fix

- Make the changes, one concern per commit where it helps the reviewer: `fix: <what> (review)` in imperative mood, `Refs #<n>` in the body.
- Re-run what the change touches: the matching review skill (`review-terraform`, `review-ansible`, `review-kubernetes`), or `update-golden-path` in the golden-path repo. A new Blocking or Should fix finding is fixed before pushing.
- Push to the PR branch (`git push`). Never `--force`.

## 4. Reply and resolve

For each thread, write the reply to a temp file and send it with `bash <skill-dir>/scripts/pr-threads.sh reply <thread-id> <file>`:

- **Fix:** `Fixed in <short sha>: <what changed>.` Then `pr-threads.sh resolve <thread-id>`.
- **Answer:** the answer, plainly. Leave it open: the reviewer resolves it when satisfied.
- **Disagree:** why (cite the issue, standard or rule), and the new issue if one was filed. Leave it open for the reviewer.

Review summaries and PR conversation comments that ask something: answer with `gh pr comment <pr> --body-file <file>`.

The card stays in **Review**.

## 5. Report

Lead with one line: **Review handled: N fixed, N answered, N disagreed** and how many threads are still open for the reviewer.

| Thread | File:line | Group | Result |
|---|---|---|---|
| short summary | path:line | Fix / Answer / Disagree | Fixed in `<sha>`, resolved / replied, open for reviewer |

Then the commits pushed, the checks re-run, **Not verified:** (e.g. CI still running), and the next step: the owner reviews the replies, resolves what is left and merges.
