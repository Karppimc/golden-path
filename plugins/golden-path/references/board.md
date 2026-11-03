# How we use the board

GitHub Projects board with columns: **Todo → In Progress → Review → Done**.

| Event | Column | Who moves it |
|---|---|---|
| Issue created and triaged | Todo | Author |
| Branch created (`pick-issue`) | In Progress | Skill |
| PR opened (`create-pr`) | Review | Skill |
| PR merged | Done | Automation / `cleanup-merged-branch` |

- Every issue has: a clear title, acceptance criteria as a checklist, labels (`terraform`, `ansible`, `kubernetes`, `docs`, `bug`).
- An issue's spec is the source of truth. If the spec leaves something out on purpose, note it as an `[Observation]`, not a defect.
- Use `gh issue view`, `gh project item-list` and `gh project item-edit` for board operations.
