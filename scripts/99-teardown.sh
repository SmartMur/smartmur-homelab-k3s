#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# 99-teardown.sh — Destroy the entire k3s cluster and VMs
# WARNING: This is DESTRUCTIVE — all data will be lost unless backed up.
# ──────────────────────────────────────────────────────────────────────────────
set -euo pipefail

RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'; NC='\033[0m'

echo -e "${RED}WARNING: This will DESTROY all VMs and cluster resources.${NC}"
echo -e "${YELLOW}Ensure all data is backed up from TrueNAS NFS shares before proceeding.${NC}"
echo ""
read -rp "Type 'DESTROY' to confirm: " confirm
[[ "$confirm" == "DESTROY" ]] || { echo "Aborted."; exit 0; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TF_DIR="$SCRIPT_DIR/../terraform"

echo -e "${YELLOW}[1/3] Removing Kubernetes apps...${NC}"
kubectl delete -f "$SCRIPT_DIR/../manifests/apps/" --ignore-not-found=true 2>/dev/null || true
kubectl delete -f "$SCRIPT_DIR/../manifests/namespaces.yml" --ignore-not-found=true 2>/dev/null || true

echo -e "${YELLOW}[2/3] Uninstalling Helm charts...${NC}"
helm uninstall traefik    -n traefik         2>/dev/null || true
helm uninstall metallb    -n metallb-system  2>/dev/null || true
helm uninstall nfs-provisioner -n storage    2>/dev/null || true

echo -e "${YELLOW}[3/3] Destroying Terraform VMs...${NC}"
cd "$TF_DIR"
terraform destroy -auto-approve

rm -f "$SCRIPT_DIR/../.k3s-node-token"
rm -f "$SCRIPT_DIR/../kubeconfig-raw.yml"

echo -e "${GREEN}[✓] Teardown complete.${NC}"
