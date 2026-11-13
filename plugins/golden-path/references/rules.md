# Golden path team rules

You are working in a karppimc platform repo (Proxmox homelab, Terraform, Ansible, k3s). These rules apply in every session. Details live in the plugin's `references/` folder; read them only when a task needs them.

## Language
- Artefacts (code, comments, commit messages, PRs, issues, docs) are written in English.
- Talk to the user in the language they write in.

## Work items
- Every change starts from a GitHub issue. If there is none, ask before creating one.
- A new issue goes on the board in Todo: `bash <plugin files>/scripts/board-move.sh <n> Todo` after `gh issue create --project <board>`.
- Branch from an up-to-date `main`: `feature/<issue>-<short-slug>` or `fix/<issue>-<short-slug>`.
- Never commit or push directly to `main`.

## Pull requests
- Open PRs with `/golden-path:create-pr`. Do not open them by hand.
- Every PR links its issue (`Closes #<n>`) and needs one approval from someone who did not write it. In a solo repo (CODEOWNERS lists only the owner) the owner reviews the PR and their merge is the approval.
- Pushing a feature branch and opening its PR is fine. Never push to `main`, never force push, never merge or enable auto-merge: the human gate is the PR.
- Run the matching review skill before opening the PR and fix blocking findings first.

## Code
- Follow `references/coding-standards/general.md` plus the file for the language: `terraform.md`, `ansible.md` or `kubernetes.md`.
- Infrastructure is declarative and idempotent. Running the same thing twice changes nothing.
- No secrets in git: no passwords, tokens, private keys or kubeconfigs. Use variables, Ansible Vault or Kubernetes Secrets created outside the repo.
- Pin versions: Terraform providers, Ansible collections, container images (no `:latest`).

## Safety
- Never run `terraform apply`, `terraform destroy`, `ansible-playbook` without `--check`, or `kubectl apply/delete` against the cluster without the user's explicit yes in this session.
- `terraform plan`, `terraform validate`, `ansible-lint`, `--check --diff` and `kubectl diff` are always fine.
- Show the plan or diff and summarise what would change before asking.

## Reporting
- Lead with the verdict, then findings as `[Blocking]`, `[Should fix]`, `[Optional]` or `[Observation]` with `file:line` and the rule.
- Say what you did not verify.
