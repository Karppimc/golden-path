---
name: scaffold-terraform-module
description: Create a new Terraform module skeleton in the shape the golden-path Terraform standard asks for - main.tf, variables.tf, outputs.tf, versions.tf and README.md, with versions pinned like the rest of the repo and an example variable with validation. Use when the user asks to create, start or scaffold a Terraform module, or an issue calls for a new reusable module.
---

# Scaffold Terraform module

Start a new module right: the five files `terraform.md` expects, versions pinned the same way as the repo's existing Terraform, and a skeleton that already passes `review-terraform`. It only creates new files and never overwrites.

The standard lives in this plugin, two folders up from this skill: `../../references/coding-standards/terraform.md` and `general.md`. Resolve them against this skill's base directory.

## 1. Decide the inputs

- **Name:** kebab-case, what the module creates (`k3s-node`, `dns-record`). Ask if the user didn't give one.
- **Location:** default `modules/<name>/` next to the repo's Terraform root. Find the root with `git ls-files '*versions.tf'` (e.g. `infra/terraform/proxmox/` → `infra/terraform/modules/<name>/`); no Terraform in the repo yet → `modules/<name>/`. A path the user gives wins.
- **Description:** one sentence on what the module creates. It goes into `main.tf` and the README, so no placeholder is left behind.
- **Providers:** the ones the module's resources will use, by source (`bpg/proxmox`). None is fine for a module that only composes other modules.

The work needs an issue and its branch (`rules.md`); if there is none, run `/golden-path:pick-issue` first.

## 2. Create

Run from the repo root:

`bash <skill-dir>/scripts/tf-scaffold.sh <dir> --description "<one sentence>" [--provider <source>[@<constraint>]]...`

- `required_version` and each provider's constraint are copied from the repo's own `versions.tf`, so the module and the root stay in line. Not pinned in the repo: pass `--provider "<source>@~> <version>"` after checking the current version in the registry, or `--terraform-version`.
- The skeleton: `versions.tf` (pins, no `provider` block: the caller configures providers), `variables.tf` with one example variable `name` and a kebab-case `validation`, `outputs.tf` with one described output, `main.tf` with the standard's reminders, `README.md` with usage, requirements, inputs and outputs.

| Exit | Meaning | Do |
|---|---|---|
| 0 | Created | Go on |
| 2 | Usage, or the name isn't kebab-case | Fix the arguments |
| 3 | The folder already has `.tf` files or a README | Nothing was written. Pick another folder or work in the existing module |
| 4 | A version can't be determined | Pass the constraint as the message says |

## 3. Check

Run `/golden-path:review-terraform` on the new folder. The untouched skeleton passes with no Blocking or Should fix findings; anything else is a bug in this skill, so say so.

## 4. Hand over

Tell the user what is theirs to do next, or do it if the issue asks for the module's content:

- replace the example `name` variable and output with the real ones, each with `description`, `type` and `validation` where it applies,
- keep the README's Inputs and Outputs tables in step with them,
- call the module from the root configuration with `for_each` where the things have identity.

## 5. Report

Lead with one line: **Module `<name>` created in `<dir>`**, or why not.

| Item | Result |
|---|---|
| Files | the five files, as links |
| `required_version` | constraint, and where it came from |
| Providers | source and constraint, and where each came from |
| review-terraform | Verdict |

End with **Not verified:** (e.g. `tflint` not installed), and the next step: fill in the module, then `/golden-path:create-pr`.
