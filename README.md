# golden-path

A Claude Code plugin that gives every repo in my homelab platform the same rules, the same skills and the same way of working, so the result no longer depends on who wrote the prompt.

It is the "paved road" of an Internal Developer Platform, applied to AI-assisted development: install once per person, nothing to copy into each repo.

Used by [homelab-platform](https://github.com/karppimc/homelab-platform) (Proxmox, Terraform, Ansible, k3s).

**9 skills · 1 rules file, loaded every session · 2 commands to install · 0 files you must add per repo**

## Why

| Problem | Fix |
|---|---|
| A `CLAUDE.md` copied into every repo drifts apart | One rules file, loaded at session start by a hook |
| Create the PR, link the issue, request a reviewer, move the card — by hand, every time | Skills that run the procedure |
| Every person gets a different Claude | Everyone installs the same versioned plugin |

## Install

You need the `claude` CLI, and `gh` and `jq` for the skills:

```bash
curl -fsSL https://claude.ai/install.sh | bash   # Claude Code CLI
gh auth login --web -s project                    # project scope: skills move board cards
```

Then, in a terminal:

```bash
claude plugin marketplace add karppimc/golden-path
claude plugin install golden-path@golden-path
```

Start a new Claude Code session afterwards; plugins load at session start.

**VS Code:** the extension has no `/plugin` command ("/plugin isn't available in this environment"). Install with the two commands above in the terminal of the same machine (in WSL, the WSL terminal). The extension and the CLI share `~/.claude`, so the plugin shows up in the extension's next session; type `/golden-path:` to see the skills.

Or let a repo suggest it: add this to the repo's `.claude/settings.json` and anyone who opens it in Claude Code is asked to install the plugin.

```json
{
  "extraKnownMarketplaces": {
    "golden-path": {
      "source": { "source": "github", "repo": "karppimc/golden-path" }
    }
  },
  "enabledPlugins": {
    "golden-path@golden-path": true
  }
}
```

To turn it off in a single repo, set `"golden-path@golden-path": false` in that repo's settings.

## Updating

A change reaches people only when `version` in `plugin.json` goes up; CI makes sure every plugin change bumps it. To get the latest version:

```bash
claude plugin marketplace update golden-path
claude plugin update golden-path@golden-path
claude plugin list        # shows the installed version
```

Then start a new session. Auto-update can be turned on per marketplace from the `/plugin` menu of the terminal CLI.

## Skills

| Skill | What it does |
|---|---|
| `/golden-path:pick-issue` | Reads the issue's spec, assigns it, creates the branch, moves the card to In Progress and plans the work against the standards |
| `/golden-path:review-terraform` | Runs fmt, validate and tflint, reviews the branch against the Terraform standard and gives a verdict with findings |
| `/golden-path:review-ansible` | Runs ansible-lint, yamllint and syntax-check (collections in a temp dir, no host contacted), reviews the branch against the Ansible standard and gives a verdict with findings |
| `/golden-path:review-kubernetes` | Renders Kustomize, runs kubeconform with CRD schemas, checks image pins and the repo's own Kyverno policies, `kubectl diff` only on a yes; reviews against the Kubernetes standard and gives a verdict with findings |
| `/golden-path:create-pr` | Opens the PR with the standard title and body, links the issue (`Closes #n`), checks a CODEOWNERS reviewer was requested and moves the issue's card to Review |
| `/golden-path:cleanup-merged-branch` | Checks the PR merged with nothing left behind, deletes the branch locally and on origin, updates `main`, closes the issue and moves the card to Done |
| `/golden-path:setup-branch-policy` | Creates or repairs the `main` ruleset and merge settings from `branching.md`: PR, approvals (0 in a solo repo), CI, squash only. Shows the plan, applies on a yes |
| `/golden-path:init-repo-claude` | Onboards a repo: short CLAUDE.md, CODEOWNERS, `.claude/settings.json` that suggests the plugin, `.gitignore` for the stack, labels, board link and branch policy. Only adds what is missing |
| `/golden-path:update-golden-path` | For changes to this plugin: checks the version bump (patch, minor, major), keeps the README skills table, count and rules budget in sync, and runs what CI runs locally |

Claude can also pick a skill by itself when the task matches.

The usual flow for one issue: `init-repo-claude` (once per repo) → `pick-issue` → `review-terraform` / `review-ansible` / `review-kubernetes` → `create-pr` → the owner reviews and merges → `cleanup-merged-branch`. The card moves Todo → In Progress → Review → Done on its own.

## How it fits together

```
golden-path/
├── .claude-plugin/marketplace.json      # this repo is also the marketplace
└── plugins/golden-path/
    ├── .claude-plugin/plugin.json       # name + version
    ├── hooks/
    │   ├── hooks.json                   # SessionStart hook
    │   └── load-rules.sh                # prints rules.md + plugin path, only in karppimc repos
    ├── skills/                          # one folder per procedure
    ├── scripts/board-move.sh            # moves an issue's card, shared by the skills
    └── references/
        ├── rules.md                     # ~350 words, read every session
        ├── branching.md
        ├── board.md
        └── coding-standards/            # general, terraform, ansible, kubernetes
```

1. **Rules** — plugins can't ship a `CLAUDE.md`, so a small SessionStart hook hands Claude the rules. It checks the git remote and stays silent outside repos owned by `karppimc`, matched case-insensitively (override with `GOLDEN_PATH_OWNERS=owner1,owner2`).
2. **The repo's own `CLAUDE.md`** — short, only what is unique to that repo.
3. **Skills** — Claude always knows which exist and reads the full instructions only when it uses one.
4. **References** — standards and process docs. Skills read them, and so does Claude when needed. Rules stay short; details are on demand.

## Lessons built in

- **No version bump, no update.** Installed plugins only update when `version` in `plugin.json` goes up. CI fails a PR that changes the plugin without bumping it.
- **Short rules, details on demand.** Everything Claude reads every session costs context, so `rules.md` stays around 350 words.
- **Claude does the work, a human owns the result.** Every PR needs an approval from someone who didn't write it. In a repo with one maintainer, that person reviews the PR and their merge is the approval. Claude never merges. Nothing is applied to the cluster without an explicit yes.

## Developing

```bash
claude plugin validate .
claude plugin validate ./plugins/golden-path
claude --plugin-dir ./plugins/golden-path   # try local changes without installing
```

Remember to bump `version` in `plugins/golden-path/.claude-plugin/plugin.json` (semver) in every PR that changes the plugin.

## License

MIT
