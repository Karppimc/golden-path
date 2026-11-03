---
name: review-terraform
description: Review Terraform code against the golden-path Terraform standard before a PR. Use when the user asks to review, check or lint Terraform, before running create-pr on a branch that changes .tf files, or after writing Terraform for an issue.
---

# Review Terraform

Review the Terraform changes on the current branch against our standards and report a verdict the author can act on. This is a read-only review: never edit files, and never run `terraform plan`, `apply` or `destroy` unless the user says yes in this session.

The standards live in this plugin, two folders up from this skill: `../../references/coding-standards/general.md` and `../../references/coding-standards/terraform.md`. Resolve them against this skill's base directory.

## 1. Find the scope

1. Changed files: `git fetch -q origin main` then `git diff --name-only origin/main...HEAD -- '*.tf' '*.tfvars.example'`, plus uncommitted ones from `git status --porcelain`.
2. If the user named files or folders, review those instead.
3. If there are no Terraform changes, say so and stop.
4. Issue context: take the issue number from the branch name (`feature/<n>-...`, `fix/<n>-...`). If found, read it with `gh issue view <n>`. The issue defines the scope: something it deliberately leaves out is an `[Observation]`, not a defect. If `gh` is missing or not logged in, carry on and mention it.

## 2. Read the standards

Read `general.md` and `terraform.md` in full. Every finding must cite a rule from them by its heading or bullet.

## 3. Run the mechanical checks

Run `bash <skill-dir>/scripts/tf-checks.sh <changed dirs>`. It runs `terraform fmt -check`, `terraform init -backend=false` + `validate` and `tflint` when installed, and never touches state. A missing tool is reported under "Not run": list it in the report, don't install anything without asking.

## 4. Read the code

Read every changed `.tf` file in full, and enough of the surrounding module to judge it. Check:

- **Layout:** files in the right place (`versions.tf`, `variables.tf`, `outputs.tf`...), modules have a README.
- **Versions:** `required_version` set, providers pinned with `~>`.
- **Variables:** `description` + `type` on all, `validation` for IPs/sizes/names, `sensitive = true` where needed.
- **Outputs:** described, nothing secret unless marked sensitive.
- **Resources:** `for_each` over `count` for things with identity, no hardcoded IPs/node names/storage pools inside modules, `lifecycle` rules explained.
- **Secrets:** no passwords, tokens, keys or real `terraform.tfvars` in git; `*.tfstate*` ignored. Any hit is `[Blocking]`.
- **DRY:** a value written twice should be a local or variable.
- **Scope:** does the change do what the issue asks, and nothing extra?

## 5. Report

Lead with one line: **Verdict: ready for PR**, **Verdict: fix before PR** (any Blocking or Should fix) or **Verdict: can't tell** (checks couldn't run and the risk is real).

Then findings, most severe first, each as:

```
[Blocking|Should fix|Optional|Observation] path/file.tf:<line>  Rule: <rule>
  What is wrong, in one or two sentences.
  Suggested fix: <concrete change>
```

Then a checklist table:

| Check | Result |
|---|---|
| fmt | Pass / Fail / Not run |
| validate | ... |
| tflint | ... |
| Layout and naming | ... |
| Versions pinned | ... |
| Variables and validation | ... |
| Outputs | ... |
| Secrets | ... |
| Scope from the issue | ... |

End with **Not verified:** what you couldn't check (e.g. `plan` against Proxmox, a missing tool), and one next step: fix the findings, or run `/golden-path:create-pr`. Offer to apply Optional fixes; don't apply them unasked.
