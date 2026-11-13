---
name: review-ansible
description: Review Ansible code against the golden-path Ansible standard before a PR. Use when the user asks to review, check or lint Ansible playbooks, roles or inventory, before running create-pr on a branch that changes Ansible files, or after writing Ansible for an issue.
---

# Review Ansible

Review the Ansible changes on the current branch against our standards and report a verdict the author can act on. This is a read-only review: never edit files, never run a playbook against hosts, and never run `--check --diff` unless the user says yes in this session.

The standards live in this plugin, two folders up from this skill: `../../references/coding-standards/general.md` and `../../references/coding-standards/ansible.md`. Resolve them against this skill's base directory.

## 1. Find the scope

1. Changed files: `git fetch -q origin main` then `git diff --name-only origin/main...HEAD -- '*.yml' '*.yaml' '*.j2' 'ansible.cfg'`, plus uncommitted ones from `git status --porcelain`. Keep the ones that belong to Ansible: under the directory with `ansible.cfg`, or playbooks, roles, inventory, `group_vars`/`host_vars`, `requirements.yml`.
2. If the user named files or folders, review those instead.
3. No Ansible changes: say so and stop.
4. Issue context: take the issue number from the branch name (`feature/<n>-...`, `fix/<n>-...`) and read it with `gh issue view <n>`. The issue defines the scope: something it deliberately leaves out is an `[Observation]`, not a defect. If `gh` is missing or not logged in, carry on and mention it.

## 2. Read the standards

Read `general.md` and `ansible.md` in full. Every finding must cite a rule from them by its heading or bullet, or the ansible-lint rule id.

## 3. Run the mechanical checks

Run `bash <skill-dir>/scripts/ansible-checks.sh <changed paths>`. From the directory holding `ansible.cfg` it:

- installs the collections in `requirements.yml` into a temp dir (never into the project), so modules from them resolve,
- runs `ansible-lint --offline` (pep8 output, the last profile met is in the summary),
- runs `yamllint` and says which config it used,
- runs `ansible-playbook --syntax-check` on every playbook among the paths; a playbook that needs the vault password to parse is reported as not checked,
- never contacts a managed host, and leaves no `.ansible/` behind.

A missing tool or a failed collection install is listed under "Not run": put it in the report, don't install anything without asking.

How to weigh the output:

- ansible-lint failures are findings at the severity of the rule they break (see step 4). `syntax-check[...]` and `internal-error` are `[Blocking]`.
- yamllint with **no repo config** runs its defaults (80-character lines, `---` document start). Report those as one `[Optional]` finding suggesting a repo `.yamllint`, not one finding per line. With a repo config, its errors are `[Should fix]`.
- `syntax-check` FAIL is `[Blocking]`.

## 4. Read the code

Read every changed file in full, and enough of the playbook or role around it to judge it. Check:

- **Layout:** inventory per environment, `group_vars`/`host_vars`, roles as `roles/<name>/{tasks,handlers,defaults,templates}`, collections pinned in `requirements.yml`.
- **Tasks:** every task and play named, names start with a verb; FQCN modules (`ansible.builtin.copy`); modules over `shell`/`command`, and when unavoidable `changed_when`/`creates`; file modes set.
- **Idempotence:** a second run changes nothing; restarts only through handlers, never unconditionally.
- **Variables:** role defaults in `defaults/main.yml` with a comment each; snake_case; no value written twice.
- **Secrets:** only through Vault or environment lookups; vault password files never committed (check `ansible.cfg`'s `vault_password_file` points outside the repo); `no_log: true` on tasks that handle secrets. A plaintext secret is `[Blocking]`.
- **Scope:** does the change do what the issue asks, and nothing extra?

## 5. Report

Lead with one line: **Verdict: ready for PR**, **Verdict: fix before PR** (any Blocking or Should fix) or **Verdict: can't tell** (checks couldn't run and the risk is real).

Then findings, most severe first, each as:

```
[Blocking|Should fix|Optional|Observation] path/file.yml:<line>  Rule: <rule>
  What is wrong, in one or two sentences.
  Suggested fix: <concrete change>
```

Then a checklist table:

| Check | Result |
|---|---|
| ansible-lint (profile met) | Pass / Fail / Not run |
| yamllint (config) | ... |
| syntax-check | ... per playbook, or "needs vault password" |
| Layout | ... |
| Task names and FQCN | ... |
| Idempotence and handlers | ... |
| Variables and defaults | ... |
| Secrets and no_log | ... |
| Scope from the issue | ... |

End with **Not verified:** what you couldn't check (e.g. `--check --diff` against real hosts, a vaulted playbook, a missing tool), and one next step: fix the findings, or run `/golden-path:create-pr`. Offer to apply Optional fixes; don't apply them unasked. Offer `--check --diff` against a host only as a question.
