#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# 02-cluster-setup.sh — Install k3s cluster via Ansible
# ──────────────────────────────────────────────────────────────────────────────
set -euo pipefail

GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'
log() { echo -e "${GREEN}[✓]${NC} $*"; }
die() { echo -e "${RED}[✗]${NC} $*"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ANSIBLE_DIR="$SCRIPT_DIR/../ansible"

command -v ansible-playbook &>/dev/null || die "ansible-playbook not found. Run scripts/00-install-tools.sh"

# ── Set k3s cluster token (required for worker join) ─────────────────────────
if [[ -z "${K3S_TOKEN:-}" ]]; then
  read -rsp "Enter K3S_TOKEN (cluster join secret, min 20 chars): " K3S_TOKEN
  echo ""
  [[ ${#K3S_TOKEN} -ge 20 ]] || die "K3S_TOKEN must be at least 20 characters"
  export K3S_TOKEN
fi

# ── Test connectivity ─────────────────────────────────────────────────────────
log "Testing Ansible connectivity..."
ansible -i "$ANSIBLE_DIR/inventory.yml" k3s_cluster -m ping \
  --private-key ~/.ssh/id_ed25519 || die "Cannot reach all nodes. Check VMs are running."

# ── Run k3s playbook ──────────────────────────────────────────────────────────
log "Installing k3s cluster..."
ansible-playbook \
  -i "$ANSIBLE_DIR/inventory.yml" \
  "$ANSIBLE_DIR/playbook-k3s.yml" \
  --private-key ~/.ssh/id_ed25519 \
  -v

# ── Verify ────────────────────────────────────────────────────────────────────
log "Verifying cluster..."
kubectl get nodes -o wide

log "Cluster ready. Next: run scripts/03-storage-setup.sh"
