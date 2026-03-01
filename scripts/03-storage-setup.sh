#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# 03-storage-setup.sh — Configure TrueNAS NFS, MetalLB, Traefik, StorageClass
# ──────────────────────────────────────────────────────────────────────────────
set -euo pipefail

GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'
log() { echo -e "${GREEN}[✓]${NC} $*"; }
die() { echo -e "${RED}[✗]${NC} $*"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ANSIBLE_DIR="$SCRIPT_DIR/../ansible"

command -v helm &>/dev/null          || die "helm not found. Run scripts/00-install-tools.sh"
command -v kubectl &>/dev/null       || die "kubectl not found. Run scripts/00-install-tools.sh"
command -v ansible-playbook &>/dev/null || die "ansible-playbook not found."

# ── Test kubectl ──────────────────────────────────────────────────────────────
kubectl cluster-info &>/dev/null || die "Cannot reach k3s cluster. Is ~/.kube/config set?"

# ── Run NFS + MetalLB + Traefik playbook ─────────────────────────────────────
log "Configuring TrueNAS NFS shares + Kubernetes storage + ingress..."
ansible-playbook \
  -i "$ANSIBLE_DIR/inventory.yml" \
  "$ANSIBLE_DIR/playbook-nfs.yml" \
  --private-key ~/.ssh/id_ed25519 \
  -v

# ── Verify StorageClass ───────────────────────────────────────────────────────
log "Verifying storage..."
kubectl get storageclass
kubectl get pods -n storage

# ── Verify MetalLB ────────────────────────────────────────────────────────────
log "Verifying MetalLB..."
kubectl get pods -n metallb-system

# ── Verify Traefik ────────────────────────────────────────────────────────────
log "Verifying Traefik..."
kubectl get pods -n traefik
kubectl get svc  -n traefik

TRAEFIK_IP=$(kubectl get svc traefik -n traefik -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "pending")
log "Traefik LoadBalancer IP: $TRAEFIK_IP"
log "Add to /etc/hosts or DNS: $TRAEFIK_IP  *.lab.local"

log "Storage setup complete. Next: run scripts/04-deploy-apps.sh"
