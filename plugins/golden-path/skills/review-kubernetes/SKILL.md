---
name: review-kubernetes
description: Review Kubernetes manifests, Kustomize and Kyverno policies against the golden-path Kubernetes standard before a PR. Use when the user asks to review, check or validate Kubernetes YAML, Argo CD apps, Kustomize overlays or policies, before running create-pr on a branch that changes manifests, or after writing manifests for an issue.
---

# Review Kubernetes

Review the Kubernetes changes on the current branch against our standards and report a verdict the author can act on. This is a read-only review: never edit files and never `kubectl apply`, `delete`, `create` or `patch`. `kubectl diff` runs only after the user says yes in this session.

The standards live in this plugin, two folders up from this skill: `../../references/coding-standards/general.md` and `../../references/coding-standards/kubernetes.md`. Resolve them against this skill's base directory.

## 1. Find the scope

1. Changed files: `git fetch -q origin main` then `git diff --name-only origin/main...HEAD -- '*.yaml' '*.yml'`, plus uncommitted ones from `git status --porcelain`. Keep the Kubernetes ones: manifests (`apiVersion:` + `kind:`), `kustomization.yaml` and the dirs around it, Helm charts and values, Kyverno policies.
2. If the user named files or folders, review those instead.
3. No Kubernetes changes: say so and stop.
4. Issue context: take the issue number from the branch name and read it with `gh issue view <n>`. Something the issue deliberately leaves out is an `[Observation]`, not a defect. If `gh` is missing or not logged in, carry on and mention it.

## 2. Read the standards

Read `general.md` and `kubernetes.md` in full. Every finding cites a rule from them, a Kyverno policy name, or the kubeconform error.

## 3. Run the mechanical checks

Run `bash <skill-dir>/scripts/k8s-checks.sh <changed paths>`. It:

- sorts the YAML into manifests, Kustomize dirs, Helm charts and other YAML (usually Helm values, listed but not validated),
- renders each Kustomize dir (`kubectl kustomize`) and checks the render instead of its files,
- runs `kubeconform -strict` with the built-in schemas plus the community CRD catalog (Argo CD, Kyverno and others; needs network); resources without a schema are counted as "no schema",
- lists `image:` lines without a tag or digest, or with `:latest`,
- when the repo has Kyverno policies (`ClusterPolicy`/`Policy`, or 1.15+ `ValidatingPolicy` and friends): runs `kyverno test` on dirs with `kyverno-test.yaml`, and `kyverno apply` of those policies to the manifests,
- leaves `kubectl diff` out unless called with `--diff`.

A missing tool is listed under "Not run": put it in the report, don't install anything without asking. Helm charts aren't rendered yet: report that as not verified.

**`kubectl diff`:** if a context exists (`kubectl config current-context`) and the change is to something the cluster runs, ask: "Run `kubectl diff` against context `<ctx>`? It only reads." On yes, rerun with `--diff` and summarise what would change. Never anything beyond diff.

How to weigh the output:

- kubeconform `invalid` or `error`, a failed Kustomize build, a failed `kyverno test`: `[Blocking]`.
- A repo Kyverno policy failing on a manifest: `[Blocking]` if the policy is `Enforce`/`Deny`, else `[Should fix]`. Check for a matching `PolicyException` in the repo first.
- Unpinned or `:latest` image: `[Should fix]` (`[Blocking]` if a repo policy enforces it).
- "no schema" resources: `[Observation]`, listed by kind.

## 4. Read the manifests

Read every changed file in full. For Argo CD `Application`s also read the values file they point at. Check:

- **Structure:** one kind per file or Kustomize `base/` + `overlays/<env>/`; `app.kubernetes.io/name`, `part-of`, `managed-by` labels; explicit namespace, never `default`.
- **Workloads:** image pinned (digest for third-party images preferred); `resources.requests` and `limits` per container; readiness and liveness probes for long-running services; `securityContext` with `runAsNonRoot`, `allowPrivilegeEscalation: false`, `readOnlyRootFilesystem` where the app allows.
- **Argo CD apps:** chart `targetRevision` pinned (no `*`, `HEAD` or branch for third-party charts), destination namespace explicit, sync policy deliberate (`prune`/`selfHeal` only where intended).
- **Config and secrets:** config in ConfigMaps; no `Secret` with real data in git unless sealed/SOPS-encrypted; no credentials in env literals or Helm values. A plaintext secret is `[Blocking]`.
- **Policies:** a new or changed Kyverno policy has a test (`kyverno-test.yaml`) with good and bad resources; exceptions are narrow (one workload) and explain why.
- **Scope:** does the change do what the issue asks, and nothing extra?

## 5. Report

Lead with one line: **Verdict: ready for PR**, **Verdict: fix before PR** (any Blocking or Should fix) or **Verdict: can't tell** (checks couldn't run and the risk is real).

Then findings, most severe first, each as:

```
[Blocking|Should fix|Optional|Observation] path/file.yaml:<line>  Rule: <rule>
  What is wrong, in one or two sentences.
  Suggested fix: <concrete change>
```

Then a checklist table:

| Check | Result |
|---|---|
| Kustomize build | Pass / Fail / none |
| kubeconform -strict | valid / invalid / no schema counts |
| Images pinned | ... |
| Kyverno test / apply | ... |
| kubectl diff | Not run / no differences / summary |
| Labels and namespaces | ... |
| Resources, probes, securityContext | ... |
| Argo CD apps | ... |
| Secrets | ... |
| Scope from the issue | ... |

End with **Not verified:** what you couldn't check (Helm renders, resources without schema, the cluster without `kubectl diff`, a missing tool), and one next step: fix the findings, or run `/golden-path:create-pr`. Offer to apply Optional fixes; don't apply them unasked.
