# Coding standards: Kubernetes manifests

## Structure
- One resource kind per file, or Kustomize `base/` + `overlays/<env>/`.
- Every resource has `app.kubernetes.io/name`, `app.kubernetes.io/part-of` and `app.kubernetes.io/managed-by` labels.
- Namespaces are explicit; nothing goes in `default`.

## Workloads
- Image tags pinned (no `:latest`), preferably by digest for third-party images.
- `resources.requests` and `resources.limits` set for every container.
- `readinessProbe` and `livenessProbe` for long-running services.
- `securityContext`: `runAsNonRoot: true`, `allowPrivilegeEscalation: false`, `readOnlyRootFilesystem: true` where the app allows it.

## Config and secrets
- Config in ConfigMaps; Secrets are created outside git (or sealed/SOPS-encrypted).
- No credentials in env literals.

## Checks a review runs
1. `kubectl kustomize` / `kustomize build` renders without errors
2. `kubeconform -strict` if installed
3. `kubectl diff` only with the user's permission and cluster access
