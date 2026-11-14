---
name: plan-feature
description: Plan and build a larger issue in four steps - research the issue, code and standards, write a plan and wait for a yes, turn it into a todo list, then implement and review. Use when the user asks to plan a feature or a bigger change, when an issue creates something new (a module, role, policy set, skill), touches several areas or running infrastructure, or when pick-issue hands a larger issue over.
---

# Plan feature

Take an issue that is too big to just start typing: **research → plan → todo → implement**. The plan is agreed with the user before any file changes, and it is written down on the issue so it survives the session.

The process lives in this plugin, two folders up from this skill: `../../references/rules.md`, `branching.md`, `board.md` and `coding-standards/`. Resolve them against this skill's base directory.

No file is changed before the user says yes to the plan. The safety rules in `rules.md` apply throughout: `plan`, `validate`, lint, `--check --diff` and `kubectl diff` are fine; `apply`, `destroy`, real playbook runs and `kubectl apply/delete` need the user's explicit yes in this session.

## 0. Start from an issue and a branch

- There is an issue number and you are on its branch (`feature/<n>-...`): go on.
- No branch yet: run `/golden-path:pick-issue <n>` first; it assigns the issue, creates the branch and moves the card, then hands back here.
- No issue: the work needs one (`rules.md`). Ask before creating it; a new issue goes on the board in Todo (`board.md`).

## 1. Research

Read before proposing anything:

1. **The issue:** `gh issue view <n> --json title,body,labels,comments`. The acceptance criteria are the definition of done. Note what the spec leaves out on purpose.
2. **The standards:** `general.md` plus the file for each language the work touches.
3. **The code:** what exists where the change goes, how similar things are already done in this repo (naming, layout, variables), what depends on the parts you will change. For infrastructure, also the current state when it is cheap and read-only: `terraform plan`, `kubectl get`, inventory.
4. **Outside facts** the plan depends on (a provider's arguments, a chart's values, an API): check them instead of assuming, and say where from.

Write down, briefly:

- **Found:** what is there today and what the change will build on.
- **Constraints:** standards, existing conventions and dependencies that shape the solution.
- **Open questions:** anything the spec doesn't decide. Ask them now, together, before planning around a guess.

## 2. Plan

One page at most:

- **Approach:** the solution in two or three sentences, and the alternative you rejected if there was a real choice, with the reason.
- **Changes:** files to create or change, in order, one line each on what and why.
- **Risks:** what could break or surprise (running workloads, state, secrets, a migration), and how the plan limits it.
- **Testing:** what will prove each acceptance criterion: commands, expected results, what needs the user's yes (`--check --diff`, `kubectl diff` against the cluster).
- **Out of scope:** things noticed that the issue doesn't ask for, as candidate issues.
- **Size:** if this is more than one reviewable PR, propose the split (separate issues) instead of one large PR.

Show the plan and ask for a yes or changes. Revise until the user agrees. Then post the agreed plan as a comment on the issue (`gh issue comment <n> --body-file <file>`), headed "Plan", so the owner and any later session can find it.

## 3. Todo

Turn the plan into a todo list and keep it current while working:

- one item per acceptance criterion,
- one per thing the standards require beyond the criteria (README for a new module, variable validation, tests for a policy),
- the checks from the plan's Testing section,
- "run the review skill" and "open the PR" last.

## 4. Implement

- Work through the todo list in the plan's order. One concern per commit: Conventional Commit subject, `Refs #<n>` in the body.
- If the plan turns out wrong (a fact was different, a risk is bigger), stop, say what changed and agree a new plan. Don't quietly do something else.
- Out of scope stays out: note it for the report as a suggested issue; file it only if the user wants, on the board in Todo.
- When the list is done, run the matching review skill (`/golden-path:review-terraform`, `review-ansible`, `review-kubernetes`; in the golden-path repo `/golden-path:update-golden-path`) and fix Blocking and Should fix findings.
- Then `/golden-path:create-pr`. Its "Deliberate deviations" lists where the result differs from the plan.

## 5. Report

Lead with one line: where the work is (**Plan agreed, implementing** / **Implemented, review: ready for PR** / **Waiting for your answers**).

Then:

| Acceptance criterion | Status | Proof |
|---|---|---|
| from the issue | Done / Open / Deviates | command and result, or file:line |

Then deviations from the plan, suggested new issues, **Not verified:**, and one next step.
