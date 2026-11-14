---
name: scaffold-ci-workflow
description: Generate a GitHub Actions validate workflow for the stacks in the repo - Terraform, Ansible, Kubernetes with Kyverno tests, yamllint and shellcheck - with pinned tool versions, actions pinned by commit and one aggregating validate check for the ruleset to require. Use when the user asks to add CI, a validate or lint workflow or GitHub Actions checks, when a repo has no CI so main can't be protected, or when init-repo-claude finds no check to require.
---

# Scaffold CI workflow

Give a repo the CI the golden path expects: static checks for every stack it contains, nothing that needs credentials, and one check named `validate` that the ruleset on `main` can require. Without it `setup-branch-policy` has nothing to require and `main` stays unprotected.

The process lives in this plugin, two folders up from this skill: `../../references/branching.md` (ruleset and required check) and `../../references/coding-standards/general.md` (pinned versions). Resolve them against this skill's base directory.

Never overwrite an existing workflow and never commit the `.proposed.yml` file. The workflow goes through a PR like any change; this skill doesn't push or change repo settings.

## 0. Start from an issue

The work needs an issue and its branch (`rules.md`). If there is none, ask before creating one, then `/golden-path:pick-issue`.

## 1. Detect

From the repo root: `bash <skill-dir>/scripts/ci-scaffold.sh detect`

It lists what it found and the jobs it would generate:

| Found | Job |
|---|---|
| `*.tf` | `terraform`: `fmt -check -recursive`, then `init -backend=false` and `validate` in every Terraform folder |
| YAML files | `yamllint` |
| `ansible.cfg` | `ansible`: `ansible-lint` in that folder, collections from `requirements.yml`, a placeholder when `ansible.cfg` names a vault password file |
| Manifests (`apiVersion` + `kind`), Kyverno tests | `kubernetes`: `kubeconform -strict` with CRD schemas on the manifest folders (Helm values left out), `kyverno test` |
| `*.sh` | `shellcheck` |
| always | `validate`: fails unless every other job succeeded; the only required check |

Exit 5: no stack found, nothing to generate; say so and stop. Show the list to the user and say what is left out on purpose (deploys, `tflint`, Helm rendering).

## 2. Create

`bash <skill-dir>/scripts/ci-scaffold.sh create`

- Tool versions are the ones installed on this machine, so CI runs what is run locally. Exit 4 names a tool that isn't installed: ask the user for the version to pin and pass it (`--kyverno-version 1.19.1`). For Kyverno, use the version running in the cluster.
- Actions are pinned by commit SHA and release binaries by checksum, both looked up now (needs `gh` and network; exit 1 if that fails).
- No yamllint config in the repo: it creates a moderate `.yamllint` (160 columns), because yamllint's defaults fail most repos.
- Exit 3: `validate.yml` already exists. Nothing was overwritten; a proposal is in `.github/workflows/validate.proposed.yml` with the diff printed. Go through the differences with the user, merge what they want into the real file, and delete the proposal.

## 3. Check before the PR

A workflow can be valid YAML and still fail on its first run, so run what the jobs run:

- `yamllint .` (includes the new workflow),
- per stack, the matching review skill's checks: `/golden-path:review-terraform`, `/golden-path:review-ansible`, `/golden-path:review-kubernetes`,
- read the generated file once: paths, versions and the `needs:` list of `validate`.

A check that fails locally will fail in CI. Fix the code or tell the user what the first run will show; don't loosen the workflow to make it pass.

## 4. Hand over

- Commit (`ci: add validate workflow`), then `/golden-path:create-pr`. The PR's own run is the real test: watch it and fix what it shows before calling the work done.
- After the merge, `validate` has run on `main` and `/golden-path:setup-branch-policy` can require it.
- Pins age. Tell the user that updating them is a normal PR, and that Dependabot or Renovate can open those PRs.

## 5. Report

Lead with one line: **CI workflow created: jobs `<list>` + `validate`**, **proposal written** (workflow existed), or why nothing was generated.

| Item | Result |
|---|---|
| Jobs | the stacks covered, and what each runs |
| Tool versions | each version and that it came from this machine or an argument |
| Pins | actions by SHA, binaries by checksum |
| `.yamllint` | created / already present |
| Local checks | Pass / Fail per stack |
| First CI run | Pass / Fail / not run yet |

End with **Not verified:** (the first real run if the PR isn't open yet, tools not installed locally), and the next step: `/golden-path:create-pr`, then `/golden-path:setup-branch-policy` after the merge.
