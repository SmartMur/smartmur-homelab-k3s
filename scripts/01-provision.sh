#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# 01-provision.sh — Provision VMs on Proxmox via Terraform
# Pre-requisites:
#   - Proxmox API token created (Datacenter → Permissions → API Tokens)
#   - Ubuntu 22.04 cloud-init template at VM ID 9000 on both Proxmox hosts
#     (run scripts/00-create-proxmox-template.sh first if needed)
#   - SSH public key available at ~/.ssh/id_ed25519.pub
# Run: bash scripts/01-provision.sh
# ──────────────────────────────────────────────────────────────────────────────
set -euo pipefail

GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'
log() { echo -e "${GREEN}[✓]${NC} $*"; }
die() { echo -e "${RED}[✗]${NC} $*"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TF_DIR="$SCRIPT_DIR/../terraform"

# ── Validate prerequisites ────────────────────────────────────────────────────
command -v terraform &>/dev/null || die "terraform not found. Run scripts/00-install-tools.sh"
[[ -f "$TF_DIR/terraform.tfvars" ]] || die "terraform/terraform.tfvars not found. Copy from terraform.tfvars.example and fill in."
[[ -n "${TF_VAR_proxmox_api_token:-}" ]] || \
  grep -q "proxmox_api_token" "$TF_DIR/terraform.tfvars" || \
  die "TF_VAR_proxmox_api_token not set. Export it or set it in terraform.tfvars"

# ── Terraform init & plan ─────────────────────────────────────────────────────
log "Initializing Terraform..."
cd "$TF_DIR"
terraform init -upgrade

log "Planning infrastructure..."
terraform plan -out=tfplan

echo ""
read -rp "Apply this plan? (yes/no): " confirm
[[ "$confirm" == "yes" ]] || { echo "Aborted."; exit 0; }

# ── Terraform apply ───────────────────────────────────────────────────────────
log "Provisioning VMs..."
terraform apply tfplan

log "Outputs:"
terraform output

# ── Wait for VMs to be reachable ──────────────────────────────────────────────
log "Waiting for VMs to become reachable via SSH..."
MASTER_IP=$(terraform output -raw k3s_master_ip 2>/dev/null || echo "192.168.100.110")

for ip in "$MASTER_IP" "192.168.100.111" "192.168.100.112" "192.168.100.113"; do
  echo -n "  Waiting for $ip ..."
  for i in $(seq 1 30); do
    ssh -o StrictHostKeyChecking=no -o ConnectTimeout=3 \
        -i ~/.ssh/id_ed25519 ubuntu@"$ip" true 2>/dev/null && \
        echo " ready" && break || echo -n "."
    sleep 5
  done
done

log "Provisioning complete. Next: run scripts/02-cluster-setup.sh"
