# Backup & Restore Runbook

Last updated: 2026-02-28

---

## 1. What to Back Up

| Asset | Location | Method |
|---|---|---|
| App data (PVCs on NFS) | TrueNAS `/mnt/strange/NSF_Prox/k3s/` | ZFS snapshots + replication |
| App data (local-path PVCs) | Worker node local disk | Manual copy or node snapshot |
| k3s etcd | k3s-master-01 `/var/lib/rancher/k3s/server/db/` | `k3s etcd-snapshot` |
| Terraform state | `terraform/terraform.tfstate` (local, gitignored) | Copy to secure off-host location |
| Terraform vars | `terraform/terraform.tfvars` (local, gitignored) | Copy to secure off-host location |
| kubeconfig | `~/.kube/config` or `kubeconfig-raw.yml` (gitignored) | Regenerated on cluster rebuild |
| Runtime secrets | Kubernetes Secrets (in-cluster only) | Export or recreate from password manager |
| Ansible inventory | `ansible/group_vars/all.yml` (tracked in git) | Git repo |
| App manifests | `manifests/` (tracked in git) | Git repo |

### local-path PVCs (not on TrueNAS)

These PVCs use `local-path` and live on the worker node, not TrueNAS NFS:

| PVC | Namespace |
|---|---|
| `authentik-postgres-data` | authentik |
| `code-server-workspace` | apps |
| `n8n-data` | n8n |

Back these up separately -- they are not covered by TrueNAS ZFS snapshots.

```bash
# Find which node hosts a local-path PV
kubectl get pv -o custom-columns='PV:.metadata.name,NODE:.spec.nodeAffinity.required.nodeSelectorTerms[0].matchExpressions[0].values[0],PATH:.spec.hostPath.path'

# Copy data off-node (example for n8n)
ssh debian@192.168.100.111 "sudo tar czf /tmp/n8n-data.tar.gz -C /var/lib/rancher/k3s/storage/ ."
scp debian@192.168.100.111:/tmp/n8n-data.tar.gz ./backups/
```

---

## 2. TrueNAS NFS Snapshots (ZFS)

All `truenas-nfs` PVC data lives under the ZFS dataset backing `/mnt/strange/NSF_Prox/k3s/`.

### Create a snapshot

```bash
ssh ray@192.168.13.69

# Snapshot the k3s NFS dataset
zfs snapshot strange/NSF_Prox/k3s@backup-$(date +%Y%m%d-%H%M%S)

# Or snapshot the parent dataset (includes all children)
zfs snapshot -r strange/NSF_Prox@backup-$(date +%Y%m%d-%H%M%S)
```

### List snapshots

```bash
ssh ray@192.168.13.69 "zfs list -t snapshot -r strange/NSF_Prox/k3s"
```

### Restore from snapshot

```bash
# Rollback to a snapshot (destroys changes after snapshot)
ssh ray@192.168.13.69 "zfs rollback strange/NSF_Prox/k3s@backup-20260228-120000"

# Or clone to a separate mount for selective recovery
ssh ray@192.168.13.69 "zfs clone strange/NSF_Prox/k3s@backup-20260228-120000 strange/k3s-recovery"
# Copy what you need from /mnt/strange/k3s-recovery/
ssh ray@192.168.13.69 "zfs destroy strange/k3s-recovery"
```

### Replicate to another pool or host

```bash
# Send snapshot to a file (off-site backup)
ssh ray@192.168.13.69 "zfs send strange/NSF_Prox/k3s@backup-20260228-120000 > /mnt/backup-drive/k3s-snapshot.zfs"

# Send to remote TrueNAS
ssh ray@192.168.13.69 "zfs send strange/NSF_Prox/k3s@backup-20260228-120000 | ssh backup-host zfs recv tank/k3s-backup"
```

### Automate via TrueNAS UI

1. TrueNAS web UI > Data Protection > Periodic Snapshot Tasks
2. Dataset: `strange/NSF_Prox/k3s`
3. Schedule: daily, retain 7 days
4. Optionally add a Replication Task to push snapshots off-box

---

## 3. k3s etcd Snapshots

k3s uses embedded etcd on the master node. Snapshots capture all cluster state (deployments, services, configmaps, etc.) but not PVC data.

### Save a snapshot

```bash
ssh debian@192.168.100.110

# On-demand snapshot
sudo k3s etcd-snapshot save --name manual-backup

# Default location: /var/lib/rancher/k3s/server/db/snapshots/
```

### List snapshots

```bash
ssh debian@192.168.100.110 "sudo k3s etcd-snapshot list"
```

### Copy snapshots off-node

```bash
scp debian@192.168.100.110:/var/lib/rancher/k3s/server/db/snapshots/manual-backup* ./backups/
```

### Restore from snapshot

```bash
ssh debian@192.168.100.110

# Stop k3s
sudo systemctl stop k3s

# Restore
sudo k3s server --cluster-reset --cluster-reset-restore-path=/var/lib/rancher/k3s/server/db/snapshots/manual-backup

# Start k3s
sudo systemctl start k3s
```

### Built-in automatic snapshots

k3s saves etcd snapshots every 12 hours by default, retaining 5. Verify:

```bash
ssh debian@192.168.100.110 "sudo k3s etcd-snapshot list"
```

---

## 4. Terraform State Backup

Terraform state is local (not remote backend) and gitignored.

| File | Purpose |
|---|---|
| `terraform/terraform.tfstate` | Current infrastructure state |
| `terraform/terraform.tfstate.backup` | Previous state |
| `terraform/terraform.tfvars` | Variables (contains Proxmox credentials) |

### Back up

```bash
cp terraform/terraform.tfstate backups/terraform.tfstate.$(date +%Y%m%d)
cp terraform/terraform.tfvars backups/terraform.tfvars.$(date +%Y%m%d)
```

Store copies in your password manager or encrypted off-site storage. These files contain infrastructure credentials.

### Recover without state

If state is lost, the VMs still exist. Re-import:

```bash
cd terraform
terraform init
terraform import proxmox_vm_qemu.k3s_master proxmox-pve1/qemu/110
terraform import proxmox_vm_qemu.k3s_worker[0] proxmox-pve1/qemu/111
terraform import proxmox_vm_qemu.k3s_worker[1] proxmox-pve1/qemu/112
terraform import proxmox_vm_qemu.k3s_worker[2] proxmox-pve1/qemu/113
```

Exact resource names depend on your `.tf` definitions. Check `terraform/main.tf`.

---

## 5. Secret Recovery

Runtime secrets are never committed to git. Recreate them from your password manager using the commands in `manifests/secrets/README.md`.

### Export existing secrets (before disaster)

```bash
# Dump all secrets to a local encrypted file
for ns in apps authentik n8n vaultwarden discourse; do
  kubectl get secrets -n $ns -o yaml >> /tmp/all-secrets.yml
done
# Encrypt and store securely -- never commit this file
gpg -c /tmp/all-secrets.yml
rm /tmp/all-secrets.yml
```

### Recreate from scratch

Replace all `CHANGE_ME` values with real credentials from your password manager:

```bash
# apps namespace
kubectl create secret generic code-server-secret -n apps \
  --from-literal=PASSWORD='CHANGE_ME' \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic pangolin-secret -n apps \
  --from-literal=PANGOLIN_APP_SECRET='CHANGE_ME_LONG_RANDOM_SECRET' \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic notify-channel-secrets -n apps \
  --from-literal=TELEGRAM_BOT_TOKEN='CHANGE_ME' \
  --from-literal=TELEGRAM_CHAT_ID='CHANGE_ME' \
  --from-literal=TWILIO_ACCOUNT_SID='CHANGE_ME' \
  --from-literal=TWILIO_AUTH_TOKEN='CHANGE_ME' \
  --from-literal=TWILIO_WHATSAPP_FROM='whatsapp:+14155238886' \
  --from-literal=TWILIO_WHATSAPP_TO='whatsapp:+10000000000' \
  --from-literal=ALERT_SMTP_HOST='smtp.gmail.com' \
  --from-literal=ALERT_SMTP_PORT='587' \
  --from-literal=ALERT_EMAIL_USER='CHANGE_ME' \
  --from-literal=ALERT_EMAIL_PASSWORD='CHANGE_ME' \
  --from-literal=ALERT_FROM_EMAIL='notify@kwe2.org' \
  --from-literal=ALERT_TO_EMAIL_1='you@example.com' \
  --dry-run=client -o yaml | kubectl apply -f -

# authentik namespace
kubectl create secret generic authentik-secret -n authentik \
  --from-literal=AUTHENTIK_SECRET_KEY='CHANGE_ME_LONG_RANDOM_SECRET' \
  --from-literal=POSTGRES_DB='authentik' \
  --from-literal=POSTGRES_USER='authentik' \
  --from-literal=POSTGRES_PASSWORD='CHANGE_ME' \
  --dry-run=client -o yaml | kubectl apply -f -

# n8n namespace
kubectl create secret generic n8n-secret -n n8n \
  --from-literal=DB_TYPE='sqlite' \
  --from-literal=N8N_ENCRYPTION_KEY='CHANGE_ME_LONG_RANDOM_SECRET' \
  --from-literal=N8N_USER_MANAGEMENT_JWT_SECRET='CHANGE_ME_LONG_RANDOM_SECRET' \
  --from-literal=WEBHOOK_URL='https://n8n.smartmur.ca' \
  --dry-run=client -o yaml | kubectl apply -f -

# vaultwarden namespace
kubectl create secret generic vaultwarden-secret -n vaultwarden \
  --from-literal=ADMIN_TOKEN='CHANGE_ME_LONG_RANDOM_SECRET' \
  --from-literal=DOMAIN='https://vault.smartmur.ca' \
  --dry-run=client -o yaml | kubectl apply -f -

# discourse namespace
kubectl create secret generic discourse-secret -n discourse \
  --from-literal=POSTGRESQL_PASSWORD='CHANGE_ME' \
  --from-literal=DISCOURSE_EMAIL='admin@example.com' \
  --from-literal=DISCOURSE_PASSWORD='CHANGE_ME' \
  --dry-run=client -o yaml | kubectl apply -f -
```

---

## 6. Full Cluster Restore (Bare Metal)

This rebuilds the entire cluster from scratch using the repo's bootstrap scripts.

### Prerequisites

- Proxmox hosts online (PVE1 at 192.168.100.100)
- TrueNAS online with NFS exports intact at 192.168.13.69
- Control node has: `bash`, `git`, `terraform`, `ansible`, `kubectl`, `helm`
- Repo cloned: `git clone <repo-url> && cd k3s-cluster`

### Step-by-step

```bash
# 1. Install tooling on control node
bash scripts/00-install-tools.sh

# 2. Create Proxmox VM template (skip if template already exists)
bash scripts/00-create-proxmox-template.sh

# 3. Restore terraform.tfvars from backup
cp backups/terraform.tfvars terraform/terraform.tfvars
# Or recreate from example:
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
# Edit with real Proxmox credentials

# 4. Provision VMs
bash scripts/01-provision.sh

# 5. Bootstrap k3s cluster
export K3S_TOKEN="your-token-min-20-chars"
bash scripts/02-cluster-setup.sh

# 6. Set up storage (NFS provisioner, MetalLB, Traefik)
bash scripts/03-storage-setup.sh

# 7. Recreate all runtime secrets (Section 5 above)
# ... run all kubectl create secret commands ...

# 8. Deploy all apps
bash scripts/04-deploy-apps.sh

# 9. (Optional) Restore etcd snapshot instead of fresh deploy
# If you have an etcd snapshot, use it after step 5 instead of steps 6-8:
#   sudo k3s server --cluster-reset --cluster-reset-restore-path=/path/to/snapshot
#   Then recreate any missing secrets.

# 10. Restore PVC data from TrueNAS ZFS snapshots
# If NFS data survived, PVCs auto-bind. If not:
ssh ray@192.168.13.69 "zfs rollback strange/NSF_Prox/k3s@<snapshot-name>"

# 11. Restore local-path PVC data
# Copy backed-up tarballs to the correct worker node paths

# 12. Sync Dockhand contexts
bash scripts/05-sync-dockhand-contexts.sh
```

### Restoring kubeconfig

After step 5, `02-cluster-setup.sh` generates a new kubeconfig. If you need it manually:

```bash
scp debian@192.168.100.110:~/.kube/config ./kubeconfig-raw.yml
# Update server address if using SSH tunnel
sed -i '' 's|https://127.0.0.1:6443|https://127.0.0.1:7443|' ./kubeconfig-raw.yml
export KUBECONFIG=$(pwd)/kubeconfig-raw.yml
```

---

## 7. Single App Restore

To redeploy one app without rebuilding the cluster.

### Example: restore vaultwarden

```bash
# 1. Recreate the secret
kubectl create secret generic vaultwarden-secret -n vaultwarden \
  --from-literal=ADMIN_TOKEN='real-token-from-password-manager' \
  --from-literal=DOMAIN='https://vault.smartmur.ca' \
  --dry-run=client -o yaml | kubectl apply -f -

# 2. Apply the manifest
kubectl apply -f manifests/apps/vaultwarden/vaultwarden.yml

# 3. Verify
kubectl get pods -n vaultwarden -w
```

### If PVC data is lost

```bash
# Restore from ZFS snapshot (NFS-backed PVCs)
ssh ray@192.168.13.69
zfs list -t snapshot -r strange/NSF_Prox/k3s | grep vaultwarden
zfs clone strange/NSF_Prox/k3s@<snapshot> strange/k3s-vw-recovery
cp -a /mnt/strange/k3s-vw-recovery/<vaultwarden-pvc-dir>/* /mnt/strange/NSF_Prox/k3s/<vaultwarden-pvc-dir>/
zfs destroy strange/k3s-vw-recovery

# Restart the pod to pick up restored data
kubectl rollout restart deployment/vaultwarden -n vaultwarden
```

### General pattern for any app

1. Recreate the app's secret (see Section 5 or `manifests/secrets/README.md`).
2. Apply the manifest: `kubectl apply -f manifests/apps/<app>/<app>.yml`
3. Restore PVC data from ZFS snapshot if needed.
4. Verify pod is running and healthy.

---

## 8. Validation

Run after any restore to confirm the cluster is healthy.

### Cluster health

```bash
kubectl get nodes
kubectl get pods -A
kubectl get pv
kubectl get pvc -A
```

### Storage

```bash
# NFS provisioner running
kubectl get pods -n storage

# PVCs bound
kubectl get pvc -A | grep -v Bound
# (should return nothing)

# TrueNAS NFS accessible from nodes
ssh debian@192.168.100.111 "showmount -e 192.168.13.69"
```

### Networking

```bash
# MetalLB and Traefik
kubectl get svc traefik -n traefik
# Should show EXTERNAL-IP 192.168.100.120

# IngressRoutes
kubectl get ingressroute -A
```

### App-level

```bash
# Check each app responds
for url in vault.smartmur.ca n8n.smartmur.ca home.smartmur.ca auth.smartmur.ca code.smartmur.ca blog.smartmur.ca k8s.smartmur.ca; do
  echo -n "$url: "; curl -sk -o /dev/null -w "%{http_code}" https://$url; echo
done
```

### Secrets present

```bash
kubectl get secret vaultwarden-secret -n vaultwarden
kubectl get secret n8n-secret -n n8n
kubectl get secret authentik-secret -n authentik
kubectl get secret code-server-secret -n apps
kubectl get secret discourse-secret -n discourse
kubectl get secret pangolin-secret -n apps
kubectl get secret notify-channel-secrets -n apps
```

### etcd health

```bash
ssh debian@192.168.100.110 "sudo k3s etcd-snapshot list"
```
