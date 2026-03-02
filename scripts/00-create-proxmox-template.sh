#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# 00-create-proxmox-template.sh
# Creates cloud-init VM templates on BOTH Proxmox hosts.
#
# Supports two distros:
#   Ubuntu 22.04 LTS (jammy)  — Template ID 9000, user: ubuntu
#   Debian 12 (bookworm)      — Template ID 9001, user: debian
#
# Usage:
#   bash 00-create-proxmox-template.sh            # creates BOTH templates
#   bash 00-create-proxmox-template.sh ubuntu     # Ubuntu only
#   bash 00-create-proxmox-template.sh debian     # Debian only
#
# Must be run with SSH access to root@192.168.100.100 and root@192.168.100.200
# ──────────────────────────────────────────────────────────────────────────────
set -euo pipefail

DISTRO="${1:-both}"   # ubuntu | debian | both
STORAGE="local-lvm"   # change to your storage pool (local-lvm, local-zfs, etc.)
BRIDGE="vmbr0"
SSH_KEY="$(cat ~/.ssh/id_ed25519.pub)"
PVE_HOSTS=("192.168.100.100" "192.168.100.200")

# ── Image definitions ──────────────────────────────────────────────────────────
UBUNTU_ID=9000
UBUNTU_URL="https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"
UBUNTU_IMG="ubuntu-22.04-cloud.img"
UBUNTU_USER="ubuntu"
UBUNTU_NAME="ubuntu-2204-cloud"

DEBIAN_ID=9001
DEBIAN_URL="https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-amd64.qcow2"
DEBIAN_IMG="debian-12-cloud.qcow2"
DEBIAN_USER="debian"
DEBIAN_NAME="debian-12-cloud"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log()  { echo -e "${GREEN}[✓]${NC} $*"; }
info() { echo -e "${YELLOW}[→]${NC} $*"; }

# ── Template creator ───────────────────────────────────────────────────────────
create_template() {
  local HOST="$1"
  local TMPL_ID="$2"
  local IMG_URL="$3"
  local IMG_FILE="$4"
  local CI_USER="$5"
  local VM_NAME="$6"

  info "Creating template $TMPL_ID ($VM_NAME) on $HOST..."

  ssh -o StrictHostKeyChecking=accept-new -o ServerAliveInterval=30 -o ServerAliveCountMax=10 root@"$HOST" bash <<REMOTE
set -euo pipefail
cd /tmp

echo "Downloading cloud image: $IMG_URL"
wget -q "$IMG_URL" -O "$IMG_FILE" || curl -sLo "$IMG_FILE" "$IMG_URL"

echo "Injecting qemu-guest-agent into image..."
apt-get install -yq libguestfs-tools >/dev/null 2>&1
virt-customize -a "$IMG_FILE" \
  --install qemu-guest-agent \
  --run-command 'systemctl enable qemu-guest-agent' \
  --run-command 'cloud-init clean' \
  >/dev/null 2>&1 || true

echo "Creating Proxmox VM template $TMPL_ID ($VM_NAME)..."
qm destroy $TMPL_ID --purge 2>/dev/null || true
qm create $TMPL_ID \
  --name "$VM_NAME" \
  --memory 2048 \
  --cores 2 \
  --net0 virtio,bridge=$BRIDGE \
  --scsihw virtio-scsi-pci \
  --serial0 socket \
  --vga serial0 \
  --agent enabled=1 \
  --ostype l26

qm importdisk $TMPL_ID "$IMG_FILE" $STORAGE
qm set $TMPL_ID \
  --scsi0 $STORAGE:vm-$TMPL_ID-disk-0,discard=on,iothread=1 \
  --ide2 $STORAGE:cloudinit \
  --boot c --bootdisk scsi0 \
  --ipconfig0 ip=dhcp \
  --sshkey <(echo "$SSH_KEY") \
  --ciuser $CI_USER

qm template $TMPL_ID
echo "Template $TMPL_ID ($VM_NAME) ready on $HOST"
REMOTE

  log "Template $TMPL_ID ($VM_NAME) created on $HOST"
}

# ── Main ───────────────────────────────────────────────────────────────────────
for HOST in "${PVE_HOSTS[@]}"; do
  case "$DISTRO" in
    ubuntu)
      create_template "$HOST" "$UBUNTU_ID" "$UBUNTU_URL" "$UBUNTU_IMG" "$UBUNTU_USER" "$UBUNTU_NAME"
      ;;
    debian)
      create_template "$HOST" "$DEBIAN_ID" "$DEBIAN_URL" "$DEBIAN_IMG" "$DEBIAN_USER" "$DEBIAN_NAME"
      ;;
    both|*)
      create_template "$HOST" "$UBUNTU_ID" "$UBUNTU_URL" "$UBUNTU_IMG" "$UBUNTU_USER" "$UBUNTU_NAME"
      create_template "$HOST" "$DEBIAN_ID" "$DEBIAN_URL" "$DEBIAN_IMG" "$DEBIAN_USER" "$DEBIAN_NAME"
      ;;
  esac
done

echo ""
log "Done. Available templates:"
log "  ID 9000 — Ubuntu 22.04 LTS (jammy)  →  vm_template_id = 9000  /  vm_user = \"ubuntu\""
log "  ID 9001 — Debian 12 (bookworm)       →  vm_template_id = 9001  /  vm_user = \"debian\""
log ""
log "Set in terraform/terraform.tfvars before running 01-provision.sh"
