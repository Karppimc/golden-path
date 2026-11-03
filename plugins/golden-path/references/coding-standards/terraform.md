# Coding standards: Terraform

## Layout
- `versions.tf` (required_version + required_providers, pinned with `~>`), `providers.tf`, `variables.tf`, `main.tf`, `outputs.tf`, `locals.tf` when needed.
- Reusable pieces go in `modules/<name>/` with their own `README.md`.
- No `terraform.tfvars` with real values in git; commit `terraform.tfvars.example`.

## Variables and outputs
- Every variable has `description` and `type`; add `validation` blocks for IPs, sizes and names.
- Sensitive inputs and outputs are marked `sensitive = true`.
- Every output has a `description`.

## Resources
- Use `for_each` over `count` for anything with identity (VMs, nodes).
- No hardcoded IPs, node names or storage pools inside modules — pass them in.
- `lifecycle` rules only with a comment explaining why.
- State is never committed (`*.tfstate*` in `.gitignore`).

## Checks a review runs
1. `terraform fmt -check -recursive`
2. `terraform init -backend=false && terraform validate`
3. `tflint` if installed
4. `terraform plan` only with the user's permission and credentials available
