# Coding standards: Ansible

## Layout
- `inventory/` (per environment), `group_vars/`, `host_vars/`, `roles/<name>/{tasks,handlers,defaults,templates}`, playbooks at the root.
- Collections pinned in `requirements.yml`.

## Tasks
- Every task has a `name` starting with a verb.
- Fully qualified module names (`ansible.builtin.copy`, not `copy`).
- Prefer modules over `shell`/`command`; when unavoidable, add `changed_when` / `creates`.
- Use handlers for restarts; never restart a service unconditionally.
- Role defaults in `defaults/main.yml`, with a comment for each variable.

## Secrets
- Secrets only through Ansible Vault or environment lookups. Vault password files are never committed.
- Tasks that print secrets use `no_log: true`.

## Checks a review runs
1. `ansible-lint`
2. `yamllint .`
3. `ansible-playbook --syntax-check`
4. `ansible-playbook --check --diff` only with the user's permission
