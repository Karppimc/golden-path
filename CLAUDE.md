# golden-path

A Claude Code plugin and marketplace: shared rules, skills and standards for karppimc's homelab platform repos.

Golden-path rules and skills come from the golden-path plugin; this file only adds what is unique to this repo.

## Layout
- `.claude-plugin/`: the marketplace manifest; this repo is its own marketplace.
- `plugins/golden-path/`: the plugin: `hooks/` (rules at session start), `skills/` (one folder per procedure), `scripts/` (shared by skills), `references/` (rules, process, coding standards).
- `.github/workflows/validate.yml`: JSON check, shellcheck on every plugin script, the skill linter on every skill, `claude plugin validate`, version-bump check.

## Notes
- Any change under `plugins/golden-path/` bumps `version` in `plugin.json` (patch fix, minor new skill); CI fails the PR otherwise.
- A new or renamed skill also updates the README skills table.
- New skills are made with `/golden-path:create-skill` and follow the shape of the existing ones: frontmatter with trigger phrases, numbered steps, references resolved against the skill's base directory, deterministic work in scripts, report with the verdict first and "Not verified".
- Try changes without installing: `claude --plugin-dir ./plugins/golden-path`.
