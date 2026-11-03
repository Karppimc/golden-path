# Coding standards: all languages

Read this together with the file for the language: `terraform.md`, `ansible.md` or `kubernetes.md`.

- **Declarative and idempotent.** A second run changes nothing.
- **No secrets** in code, defaults, examples or outputs. Flag anything that looks like a credential as `[Blocking]`.
- **Pinned versions** for providers, modules, collections, images and actions.
- **DRY.** A value written twice becomes a variable/local/default.
- **Naming:** kebab-case for resource and host names, snake_case for Terraform and Ansible variables.
- **Every input is documented** (description, type, sensible default or validation).
- **No TODOs** left in a PR without a linked issue.
- **Files end with a newline**, no trailing whitespace, formatter applied (`terraform fmt`, `yamllint`).
- **Small PRs:** one issue, one concern.
