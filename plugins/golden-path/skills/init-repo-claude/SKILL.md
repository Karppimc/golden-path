---
name: init-repo-claude
description: Onboard a repo to the golden path - a short repo CLAUDE.md, CODEOWNERS, .claude/settings.json that suggests the plugin, .gitignore entries for the stack, board labels, a link to the project board, and the main branch policy via setup-branch-policy. Use when the user asks to onboard, initialise or set up a repo for Claude or the golden path, or a repo has no CLAUDE.md or ruleset yet.
---

# Init repo for Claude

Bring a repo up to the golden-path baseline. Every step checks first and only adds what is missing, so a second run reports "nothing to change".

The process lives in this plugin, two folders up from this skill: `../../references/rules.md`, `branching.md`, `board.md` and `coding-standards/`. Resolve them against this skill's base directory.

GitHub settings (labels, board link, branch policy) change right away, so show what will change and get a yes first. Files go through a pull request like any other change: `main` may already be protected.

## 1. Preflight and inventory

1. `gh auth status`; stop if `gh` is missing or not logged in. Admin rights: `gh api repos/<owner>/<repo> --jq .permissions.admin`.
2. Stack, from the files in the repo: Terraform (`*.tf`), Ansible (`ansible.cfg`, `playbooks/`, `roles/`, `inventory/`), Kubernetes (manifests with `apiVersion:` + `kind:`, `kustomization.yaml`, Helm `Chart.yaml`). Also note an existing CI workflow and its check names.
3. Read what already exists: `CLAUDE.md` or `.claude/CLAUDE.md`, CODEOWNERS (`.github/`, root, `docs/`), `.claude/settings.json`, `.gitignore`, labels (`gh label list`), linked boards (`gh api graphql` on `repository.projectsV2`), rulesets.

Show the inventory as a table: item, present or missing, what you'd do.

## 2. Ask

One round of questions, only for what is missing:

- **Owners** for CODEOWNERS: default `* @<repo owner>`. More people or per-path owners → ask.
- **Repo notes** for CLAUDE.md: anything unique to this repo that Claude must know (environments, how to run plan, what never to touch). Offer to leave it at the basics.
- **Board**: list open boards with `gh project list --owner <owner>`. One → propose it. Several or none → ask; don't create a board unasked.

## 3. GitHub settings (after a yes)

1. **Labels** from `board.md`: `docs`, `bug` and one per detected stack (`terraform`, `ansible`, `kubernetes`). Create only missing ones: `gh label create <name> -c <color> -d <description>`.
2. **Board link**: `gh project link <number> --owner <owner> --repo <owner>/<repo>` if not linked.
3. **Branch policy**: run `/golden-path:setup-branch-policy`. It has its own plan and yes. No CI check on the default branch yet: skip it, say so, and offer `/golden-path:scaffold-ci-workflow` (file its issue on the board in Todo, see `board.md`); once that workflow has run on `main`, run `/golden-path:setup-branch-policy`.

## 4. Files (through a PR)

Work on a branch from `origin/main` (`chore/init-repo-claude`, no upstream). Use the onboarding issue if the user has one (`feature/<n>-init-repo-claude` and `Closes #<n>`); otherwise ask whether to create one, since every PR links an issue.

- **`CLAUDE.md`** at the repo root, only if neither `CLAUDE.md` nor `.claude/CLAUDE.md` exists. Short, only what is unique:
  ```markdown
  # <repo>

  <one-line description: from `gh repo view --json description`, or ask>

  Golden-path rules and skills come from the golden-path plugin; this file only adds what is unique to this repo.

  ## Layout
  - `<dir>/`: <one line each, top-level dirs only>

  ## Notes
  - <the user's repo notes, or remove this section>
  ```
- **`.github/CODEOWNERS`** with the owners from step 2.
- **`.claude/settings.json`**: add the marketplace and enable the plugin, merging into an existing file without dropping keys. This gives the repo its own project-scope install of the plugin, which updates separately from a user-scope install (`claude plugin update golden-path@golden-path --scope project`, run in the repo); say so in the report:
  ```json
  {
    "extraKnownMarketplaces": {
      "golden-path": { "source": { "source": "github", "repo": "karppimc/golden-path" } }
    },
    "enabledPlugins": { "golden-path@golden-path": true }
  }
  ```
- **`.gitignore`**: append only missing entries, per stack. Terraform: `.terraform/`, `*.tfstate`, `*.tfstate.*`, `*.tfvars` and `!*.tfvars.example`, `crash.log`. Ansible: `*.retry`, `.vault_pass*`. Kubernetes: `kubeconfig*`, `*.kubeconfig`.

Commit (`chore: onboard repo to the golden path`) and open the PR with `/golden-path:create-pr`. No file changes at all → no branch, no PR.

## 5. Report

Lead with one line: **Onboarded <repo>**, **already onboarded, nothing to change**, or what is left.

| Item | Result |
|---|---|
| CLAUDE.md | Created / present |
| CODEOWNERS | Created (owners) / present |
| `.claude/settings.json` | Created / merged / present |
| `.gitignore` | Entries added / present |
| Labels | Created / present |
| Board | Linked (#n) / already linked |
| Branch policy | Applied / ok / skipped (no CI) |
| PR | URL / no file changes |

End with **Not verified:** and the next step: review and merge the PR, then `/golden-path:pick-issue` for the first issue.
