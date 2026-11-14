---
name: scaffold-kyverno-policy
description: Create a new Kyverno validating policy together with its tests, in the pattern the repo's existing policies use - same API, folders and excluded namespaces, starting in Audit, with good, bad and excluded test resources that pass kyverno test as created. Use when the user asks to add, write or scaffold a Kyverno policy or a guardrail for the cluster, or when an issue calls for enforcing a rule on Kubernetes resources.
---

# Scaffold Kyverno policy

Start a policy the way the others were built: the policy, its reason, and tests with good and bad resources, all at once. A policy without tests can silently let a bad resource through or block a good one; `review-kubernetes` asks for the tests, so this skill makes them the default.

The standard lives in this plugin, two folders up from this skill: `../../references/coding-standards/kubernetes.md` and `../../references/coding-standards/general.md`. Resolve them against this skill's base directory.

This skill only creates files. Never apply a policy to the cluster, and never create a policy that starts in Deny or Enforce unless the user says so: a new rule that rejects resources on day one breaks workloads nobody checked.

## 0. Start from an issue

The work needs an issue and its branch (`rules.md`). If there is none, ask before creating one, then `/golden-path:pick-issue`.

## 1. Pin down the rule

Before creating anything, be able to say:

- **What it prevents and why**, in one or two sentences. This becomes the comment at the top of the policy; "why" is what a person blocked by it will read.
- **What it applies to:** which kinds (Pods, or workloads through their Pods), which namespaces are excluded.
- **A good, a bad and an edge example.** If you can't name a resource that should fail, the rule isn't clear yet.
- **Who would need an exception** today (a third-party chart that can't comply). Exceptions are narrow: one policy, one workload, with the reason.

## 2. Scaffold

From the repo root:

`bash <skill-dir>/scripts/kyverno-scaffold.sh <name> --description "<what it prevents and why>"`

- The name is kebab-case and says what is required or disallowed: `require-standard-labels`, `disallow-host-path`.
- It reads the repo's existing policies and follows them: the policy folder, the test folder, the excluded namespaces, and the API (`policies.kyverno.io` `ValidatingPolicy` with CEL, or `kyverno.io` `ClusterPolicy`). A repo without policies gets the new API in `policies/` and `tests/policies/`; `--policy-dir`, `--test-dir` and `--api new|classic` override.
- The policy starts in **Audit** and carries one working example rule (pods need the `app.kubernetes.io/name` label) with test pods `good-*`, `bad-*` and `excluded-*`.
- It runs `kyverno test` on the result when the CLI is installed.

| Exit | Meaning | Do |
|---|---|---|
| 0 | Created; tests pass (or kyverno isn't installed: it says so) | Go on |
| 3 | The policy or its test folder exists | Nothing written. Pick another name or edit the existing policy |
| 10 | Created, but `kyverno test` fails on the untouched skeleton | A bug in this skill or a CLI too old for the API: say so |
| 2 | Usage, bad name, or not in a git repo | Fix the arguments |

## 3. Write the rule and its tests

1. Replace the example expression (or pattern) and its message. The message tells the person what to change, not just what is wrong.
2. Rewrite `resources.yaml` for the real rule: at least two good resources, every way of getting it wrong you can think of as a `bad-*` resource, the edge cases (init containers, sidecars, optional fields missing), and one resource in an excluded namespace. List each under `pass`, `fail` or `skip` in `kyverno-test.yaml`.
3. `kyverno test <test folder>` until it passes, then the whole test root, so the other policies still pass.

## 4. Check

Run `/golden-path:review-kubernetes` on the policy and its tests. It validates the policy against its CRD schema and checks the repo's manifests against the repo's policies.

## 5. From Audit to Deny

Leave the switch out of this PR unless the issue asks for it. The order that breaks nothing:

1. Merge in Audit and let the cluster report (`PolicyReport`s).
2. Fix each finding, or give it a narrow exception that says why.
3. Then a second PR changes the action to `[Deny, Audit]` (or `Enforce`), with the clean report as its test.

## 6. Hand over and report

Commit (`feat(policies): add <name>`), then `/golden-path:create-pr`.

Lead with one line: **Policy `<name>` created, in Audit, tests: N passed**, or what is open.

| Item | Result |
|---|---|
| Policy | the file, API and where its pattern came from |
| Tests | the folder; passed / failed counts |
| Excluded namespaces | the list |
| review-kubernetes | Verdict |
| Mode | Audit, and what must happen before Deny |

End with **Not verified:** how the policy behaves in the real cluster (reports come after the merge), and the next step: review the PR, then watch the policy reports.
