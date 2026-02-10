# Copilot Instructions

## Overview

Autokube: single-command Kubernetes dev environment (`./autokube up`). Deploys a Kind cluster with ArgoCD, Vault, ESO, kgateway, SonarQube, Kyverno. Also supports external (non-Kind) clusters via `cluster.create: false`.

## Language & Style

- **All code is Bash** with `set -euo pipefail` and `trap cleanup_on_exit EXIT` in every script.
- **Documentation, comments, log messages, and help text are in Spanish.** Maintain this convention.
- Variables: `CFG_*` for config, `readonly` for constants (chart versions, namespaces).
- Quoting: always double-quote variables (`"$var"`, `"${CFG_DATA_DIR}"`).
- Idempotent operations: `helm upgrade --install`, check-before-create for namespaces/certs.

## Architecture — Three Install Modes

Determined by config in `autokube.yaml`:

| Mode | Condition | Mechanism |
|------|-----------|-----------|
| GitOps remote | `gitops.enabled` + `repoURL` set | ArgoCD syncs from Git; `gitops/apps/` is a Helm chart rendering Application CRs with multi-source pattern |
| ArgoCD local | `argocd.enabled` + no `repoURL` | ArgoCD Applications with inline values from `manifests/` |
| Imperative | `argocd.enabled: false` | Direct Helm installs via `install_*()` functions |

ArgoCD itself and Vault init/unseal/configure are **always imperative** (can't self-bootstrap).

## Key Patterns

- **Component structure**: each component has `lib/<name>.sh` with `install_<name>()` + `<name>_post_install()`.
- **Template system**: `manifests/*.tpl` use `__VAR__` placeholders replaced by `render_template()` in [lib/common.sh](../lib/common.sh) — NOT Helm templating or envsubst.
- **Kind vs External**: `is_kind_cluster()` in [lib/config.sh](../lib/config.sh) gates all divergent behavior (storage, networking, sysctl). When modifying component behavior, always consider both paths.
- **Config parsing**: `cfg_read()` wraps `yq eval "$path // \"\""`. New config keys require default handling in `load_config()`.
- **Logging**: use `log_info`, `log_success`, `log_warn`, `log_error`, `log_step`, `log_header` from `lib/common.sh` — never raw `echo`.
- **Wait/retry**: `wait_for_ready()`, `wait_for_deployment()`, `wait_for_pods()`, `retry()` (exponential backoff).
- **Helm**: always `helm upgrade --install --wait --timeout 10m` (except Vault which starts sealed).
- **Sync waves** in `gitops/apps/templates/`: -4 (metallb) → -3 (kgateway, vault) → -2 (sonarqube, kyverno) → -1 (eso) → 0 (eso-config, kyverno-policies) → 1 (routes, arc) → 2 (arc-config, arc-runner-set).

## Build & Test

```bash
./autokube up       # Full deploy — the only integration "test"
./autokube status   # Verify cluster, components, URLs, credentials
./autokube down     # Stop cluster (preserves data, Kind only)
./autokube destroy  # Delete cluster
```

No automated tests. Validation is manual via `./autokube status`.

## Security

- `data/vault/init.json` contains unseal keys + root token in plaintext (chmod 600). Never log or expose this file.
- `data/ssl/ca.key` is the CA private key. Cert generation in [lib/ssl.sh](../lib/ssl.sh) uses `sudo` for system trust store operations.
- Vault token is passed inline via `VAULT_TOKEN=...` inside pod exec — keep this pattern contained.

## Critical Rules

- **NEVER** add `Co-Authored-By` or AI attribution in commits.
- **NEVER** use GitHub-hosted runners (`ubuntu-latest`) in workflows — always `arc-runner-set` (self-hosted).
- When adding a component, update **all three install modes**: `lib/<name>.sh`, `manifests/<name>/`, and `gitops/` (apps template + components values).
- Keep chart versions pinned as `readonly` constants in their `lib/*.sh` file.
