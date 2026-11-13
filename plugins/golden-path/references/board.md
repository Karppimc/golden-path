# How we use the board

GitHub Projects board with columns: **Todo → In Progress → Review → Done**.

| Event | Column | Who moves it |
|---|---|---|
| Issue created and triaged | Todo | Author |
| Branch created (`pick-issue`) | In Progress | Skill |
| PR opened (`create-pr`) | Review | Skill |
| PR merged | Done | Automation / `cleanup-merged-branch` |

- Every issue has: a clear title, acceptance criteria as a checklist, labels (`terraform`, `ansible`, `kubernetes`, `docs`, `bug`; a repo may add its own, e.g. golden-path uses `skill` and `ci`).
- An issue's spec is the source of truth. If the spec leaves something out on purpose, note it as an `[Observation]`, not a defect.
- Use `gh issue view`, `gh project item-list` and `gh project item-edit` for board operations.
- Creating an issue, by hand or from a skill: `gh issue create --project "<board title>" ...`, then `scripts/board-move.sh <n> Todo`. Adding an item leaves `Status` empty, so without the move it shows in no column.
- Safety net: turn on the board's built-in workflow "Item added to project" → Status Todo (board → ⋯ → Workflows; UI only).
- The board is whichever open project the issue is on; skills find it from the issue at run time. The column is the single-select field `Status`.
- Board operations need the `project` scope on the gh token: `gh auth refresh -s project`.
