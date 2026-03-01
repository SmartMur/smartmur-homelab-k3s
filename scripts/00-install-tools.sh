#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# 00-install-tools.sh — Install all required tools on Mac control node
# Run once: bash scripts/00-install-tools.sh
# ──────────────────────────────────────────────────────────────────────────────
set -euo pipefail

YELLOW='\033[1;33m'; GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'
log()  { echo -e "${GREEN}[✓]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
die()  { echo -e "${RED}[✗]${NC} $*"; exit 1; }

command -v brew &>/dev/null || die "Homebrew not found. Install from https://brew.sh"

log "Installing Terraform..."
brew tap hashicorp/tap 2>/dev/null
brew install hashicorp/tap/terraform || brew upgrade hashicorp/tap/terraform

log "Installing Ansible..."
brew install ansible || true
# Install required Ansible collections
ansible-galaxy collection install community.general kubernetes.core ansible.posix

log "Installing kubectl..."
brew install kubectl || brew upgrade kubectl

log "Installing Helm..."
brew install helm || brew upgrade helm
# Add repos needed for this project
helm repo add traefik https://traefik.github.io/charts
helm repo add metallb https://metallb.github.io/metallb
helm repo add nfs-subdir-external-provisioner https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner/
helm repo update

log "Installing k3sup (optional k3s bootstrapper)..."
brew install k3sup || true

log "Verifying installations..."
echo ""
printf "%-20s %s\n" "terraform:"  "$(terraform version --json 2>/dev/null | python3 -c 'import sys,json;print(json.load(sys.stdin)["terraform_version"])' 2>/dev/null || terraform version | head -1)"
printf "%-20s %s\n" "ansible:"    "$(ansible --version | head -1)"
printf "%-20s %s\n" "kubectl:"    "$(kubectl version --client --short 2>/dev/null || kubectl version --client 2>/dev/null | head -1)"
printf "%-20s %s\n" "helm:"       "$(helm version --short)"
printf "%-20s %s\n" "k3sup:"      "$(k3sup version 2>/dev/null | head -1 || echo 'not installed')"
echo ""

log "All tools installed. Next: run scripts/01-provision.sh"
