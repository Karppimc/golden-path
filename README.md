# golden-path

A Claude Code plugin that gives every repo in my homelab platform the same rules, the same skills and the same way of working, so the result no longer depends on who wrote the prompt.

It is the "paved road" of an Internal Developer Platform, applied to AI-assisted development: install once per person, nothing to copy into each repo.

Used by [homelab-platform](https://github.com/karppimc/homelab-platform) (Proxmox, Terraform, Ansible, k3s).

## Why

| Problem | Fix |
|---|---|
| A `CLAUDE.md` copied into every repo drifts apart | One rules file, loaded at session start by a hook |
| Create the PR, link the issue, request a reviewer, move the card — by hand, every time | Skills that run the procedure |
| Every person gets a different Claude | Everyone installs the same versioned plugin |

## Install

```bash
claude plugin marketplace add karppimc/golden-path
claude plugin install golden-path@golden-path
```

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

## Skills

| Skill | What it does |
|---|---|
| `/golden-path:review-terraform` | Runs fmt, validate and tflint, reviews the branch against the Terraform standard and gives a verdict with findings |

Claude can also pick a skill by itself when the task matches.

## How it fits together

```
golden-path/
├── .claude-plugin/marketplace.json      # this repo is also the marketplace
└── plugins/golden-path/
    ├── .claude-plugin/plugin.json       # name + version
    ├── hooks/
    │   ├── hooks.json                   # SessionStart hook
    │   └── load-rules.sh                # prints rules.md, only in karppimc repos
    ├── skills/                          # one folder per procedure
    └── references/
        ├── rules.md                     # ~300 words, read every session
        ├── branching.md
        ├── board.md
        └── coding-standards/            # general, terraform, ansible, kubernetes
```

1. **Rules** — plugins can't ship a `CLAUDE.md`, so a small SessionStart hook hands Claude the rules. It checks the git remote and stays silent outside repos owned by `karppimc` (override with `GOLDEN_PATH_OWNERS=owner1,owner2`).
2. **The repo's own `CLAUDE.md`** — short, only what is unique to that repo.
3. **Skills** — Claude always knows which exist and reads the full instructions only when it uses one.
4. **References** — standards and process docs. Skills read them, and so does Claude when needed. Rules stay short; details are on demand.

## Lessons built in

- **No version bump, no update.** Installed plugins only update when `version` in `plugin.json` goes up. CI fails a PR that changes the plugin without bumping it.
- **Short rules, details on demand.** Everything Claude reads every session costs context, so `rules.md` stays around 300 words.
- **Claude does the work, a human owns the result.** Every PR needs an approval from someone who didn't write it. Nothing is applied to the cluster without an explicit yes.

## Developing

```bash
claude plugin validate .
claude plugin validate ./plugins/golden-path
claude --plugin-dir ./plugins/golden-path   # try local changes without installing
```

Remember to bump `version` in `plugins/golden-path/.claude-plugin/plugin.json` (semver) in every PR that changes the plugin.

## License

MIT
