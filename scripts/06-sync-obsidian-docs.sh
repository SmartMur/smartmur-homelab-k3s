#!/usr/bin/env bash
# Sync k3s project docs into the live Obsidian vault in the k8s obsidian app.
set -euo pipefail

NAMESPACE="${OBSIDIAN_NAMESPACE:-apps}"
APP_LABEL="${OBSIDIAN_APP_LABEL:-obsidian}"
DEPLOYMENT="${OBSIDIAN_DEPLOYMENT:-obsidian}"
VAULT_SUBDIR="${OBSIDIAN_VAULT_SUBDIR:-K3s-Cluster}"
VAULT_ROOT="/config/Obsidian Vault"
VAULT_PATH="${VAULT_ROOT}/${VAULT_SUBDIR}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="${SCRIPT_DIR}/.."
TMP_DIR="$(mktemp -d -t k3s-obsidian-sync.XXXXXX)"
trap 'rm -rf "${TMP_DIR}"' EXIT

need_file() {
  local f="$1"
  [[ -f "$f" ]] || { echo "Missing required file: $f" >&2; exit 1; }
}

need_file "${REPO_DIR}/docs/BEGINNER_JOURNEY.md"
need_file "${REPO_DIR}/docs/GETTING_STARTED.md"
need_file "${REPO_DIR}/STACK.md"
need_file "${REPO_DIR}/docs/SECURITY_RULEBOOK.md"
need_file "${REPO_DIR}/docs/DOCKHAND_HEADLAMP_WORKFLOW.md"
need_file "${REPO_DIR}/docs/OPERATIONS_AUDIT_2026-02-22.md"
need_file "${REPO_DIR}/README.md"

cat > "${TMP_DIR}/00 - Start Here.md" <<'MD'
---
title: K3s Cluster Knowledge Base
tags:
  - k3s
  - kubernetes
  - beginner
  - runbook
  - obsidian
---

# K3s Cluster Knowledge Base

Use this as your website-style index.

<details open>
<summary><strong>Documentation Menu (01-06)</strong></summary>

1. [[01 - Beginner Journey]]
2. [[02 - Getting Started (Fast Path)]]
3. [[03 - Stack Reference]]
4. [[04 - Security Rulebook]]
5. [[05 - Dockhand + Headlamp Workflow]]
6. [[06 - Operations Audit 2026-02-22]]

</details>

<details>
<summary><strong>Extra Docs</strong></summary>

- [[07 - Repo README]]

</details>
MD

cp "${REPO_DIR}/docs/BEGINNER_JOURNEY.md" "${TMP_DIR}/01 - Beginner Journey.md"
cp "${REPO_DIR}/docs/GETTING_STARTED.md" "${TMP_DIR}/02 - Getting Started (Fast Path).md"
cp "${REPO_DIR}/STACK.md" "${TMP_DIR}/03 - Stack Reference.md"
cp "${REPO_DIR}/docs/SECURITY_RULEBOOK.md" "${TMP_DIR}/04 - Security Rulebook.md"
cp "${REPO_DIR}/docs/DOCKHAND_HEADLAMP_WORKFLOW.md" "${TMP_DIR}/05 - Dockhand + Headlamp Workflow.md"
cp "${REPO_DIR}/docs/OPERATIONS_AUDIT_2026-02-22.md" "${TMP_DIR}/06 - Operations Audit 2026-02-22.md"
cp "${REPO_DIR}/README.md" "${TMP_DIR}/07 - Repo README.md"

POD="$(kubectl -n "${NAMESPACE}" get pods -l app="${APP_LABEL}" -o jsonpath='{.items[0].metadata.name}')"
[[ -n "${POD}" ]] || { echo "Could not find obsidian pod in namespace ${NAMESPACE}" >&2; exit 1; }

kubectl -n "${NAMESPACE}" exec "deploy/${DEPLOYMENT}" -- sh -lc "rm -rf \"${VAULT_PATH}\" && mkdir -p \"${VAULT_PATH}\""
kubectl cp "${TMP_DIR}/." "${NAMESPACE}/${POD}:${VAULT_PATH}"
kubectl -n "${NAMESPACE}" exec "deploy/${DEPLOYMENT}" -- sh -lc "chown -R abc:abc \"${VAULT_PATH}\" && find \"${VAULT_PATH}\" -type f -name '*.md' -exec chmod 664 {} +"

printf 'Synced %s notes to %s in %s/%s\n' "$(find "${TMP_DIR}" -type f -name '*.md' | wc -l | tr -d ' ')" "${VAULT_PATH}" "${NAMESPACE}" "${POD}"
