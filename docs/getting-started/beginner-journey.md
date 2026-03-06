---
title: k3s Beginner Journey
tags:
  - k3s
  - kubernetes
  - beginner
  - homelab
  - obsidian
  - runbook
---

# k3s Beginner Journey (From Scratch)

> Goal: take a brand-new control machine and stand up this full k3s environment end-to-end.
>
> Audience: first-time operators.
>
> Primary mode: run commands in order, do not skip phases.

## Journey Map

Tags: #journey #order #start-here

1. Prepare your control machine.
2. Create Proxmox VM templates.
3. Configure Terraform variables.
4. Provision VMs.
5. Bootstrap k3s.
6. Set up storage + ingress.
7. Create runtime secrets.
8. Deploy apps.
9. Validate and operate.

## Phase 0: Understand What This Repo Does

Tags: #phase/00 #concepts #beginner

This repo automates:

- Proxmox VM provisioning with Terraform.
- k3s bootstrap with Ansible.
- MetalLB + Traefik ingress.
- TrueNAS-backed persistent storage.
- App deployments via Kubernetes manifests.

Main entry points:

- `scripts/00-install-tools.sh` -> tools
- `scripts/01-provision.sh` -> VMs
- `scripts/02-cluster-setup.sh` -> k3s cluster
- `scripts/03-storage-setup.sh` -> NFS + MetalLB + Traefik
- `scripts/04-deploy-apps.sh` -> apps

## Phase 1: Prepare Control Machine

Tags: #phase/01 #prerequisites #macos #linux

### Required access

- SSH access to Proxmox hosts.
- Proxmox API token.
- SSH key at `~/.ssh/id_ed25519`.
- TrueNAS SSH access.

### Run

```bash
cd /Users/dre/k3s-cluster
bash scripts/00-install-tools.sh
```

### Success check

```bash
terraform version
ansible --version
kubectl version --client
helm version
```

## Phase 2: Create Proxmox Templates (One-Time)

Tags: #phase/02 #proxmox #templates

This project supports:

- Template `9000`: Ubuntu 22.04
- Template `9001`: Debian 12 (recommended in `terraform.tfvars.example`)

Run:

```bash
cd /Users/dre/k3s-cluster
bash scripts/00-create-proxmox-template.sh debian
```

If you want both:

```bash
bash scripts/00-create-proxmox-template.sh
```

## Phase 3: Configure Terraform Inputs

Tags: #phase/03 #terraform #configuration

Create your local vars file:

```bash
cd /Users/dre/k3s-cluster
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
```

Edit `terraform/terraform.tfvars` and set at minimum:

- `proxmox_host1_ip`
- `proxmox_host2_ip`
- `proxmox_api_token`
- `ssh_public_key`
- `vm_template_id` and `vm_user` (must match)
- node IPs and gateway/DNS for your LAN

Security rule:

- Never commit `terraform/terraform.tfvars`.

## Phase 4: Provision VMs

Tags: #phase/04 #terraform #provisioning

Run:

```bash
cd /Users/dre/k3s-cluster
bash scripts/01-provision.sh
```

Notes:

- The script runs `terraform init`, `plan`, then asks for confirmation.
- Type `yes` when prompted to apply.

Success check:

```bash
cd /Users/dre/k3s-cluster/terraform
terraform output
```

## Phase 5: Bootstrap k3s

Tags: #phase/05 #ansible #k3s

Set a cluster token (20+ characters):

```bash
export K3S_TOKEN='CHANGE_ME_WITH_A_LONG_RANDOM_SECRET'
```

Run:

```bash
cd /Users/dre/k3s-cluster
bash scripts/02-cluster-setup.sh
```

Success check:

```bash
kubectl get nodes -o wide
kubectl cluster-info
```

## Phase 6: Install Storage + Ingress

Tags: #phase/06 #storage #ingress #truenas #metallb #traefik

Run:

```bash
cd /Users/dre/k3s-cluster
bash scripts/03-storage-setup.sh
```

What this installs/configures:

- TrueNAS NFS shares.
- `nfs-subdir-external-provisioner`.
- MetalLB.
- Traefik.

Success checks:

```bash
kubectl get storageclass
kubectl get pods -n storage
kubectl get pods -n metallb-system
kubectl get svc -n traefik
```

## Phase 7: Create Runtime Secrets (Mandatory)

Tags: #phase/07 #secrets #security #required

Before app deployment, create required secrets.

Reference:

- `manifests/secrets/README.md`

Examples:

```bash
# apps namespace
kubectl create secret generic code-server-secret -n apps \
  --from-literal=PASSWORD='CHANGE_ME' \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic pangolin-secret -n apps \
  --from-literal=PANGOLIN_APP_SECRET='CHANGE_ME_LONG_RANDOM_SECRET' \
  --dry-run=client -o yaml | kubectl apply -f -

# authentik namespace
kubectl create secret generic authentik-secret -n authentik \
  --from-literal=AUTHENTIK_SECRET_KEY='CHANGE_ME_LONG_RANDOM_SECRET' \
  --from-literal=POSTGRES_DB='authentik' \
  --from-literal=POSTGRES_USER='authentik' \
  --from-literal=POSTGRES_PASSWORD='CHANGE_ME' \
  --dry-run=client -o yaml | kubectl apply -f -
```

## Phase 8: Deploy Apps

Tags: #phase/08 #apps #deployment

Run:

```bash
cd /Users/dre/k3s-cluster
bash scripts/04-deploy-apps.sh
```

This script:

- Applies namespaces.
- Applies local secret overlays from `manifests/secrets/*.yml` (if present).
- Applies ingress defaults.
- Deploys app manifests.
- Waits for common deployments to be ready.

Optional after deploy:

```bash
bash scripts/05-sync-dockhand-contexts.sh
```

## Phase 9: Validate Everything

Tags: #phase/09 #validation #checklist

Cluster health:

```bash
kubectl get nodes -o wide
kubectl get pods -A
kubectl get events -A --field-selector type=Warning --sort-by=.lastTimestamp | tail -n 40
```

Ingress path:

```bash
kubectl get svc traefik -n traefik
kubectl get ingressroute -A
```

Manifests + security checks:

```bash
cd /Users/dre/k3s-cluster
bash -n scripts/*.sh
pre-commit run --all-files
python3 scripts/security_scrub.py --no-history
kubectl apply --dry-run=server -R -f manifests/apps
```

## Local DNS / Hosts for First Access

Tags: #networking #dns #first-login

If you do not yet have internal DNS records, map your Traefik LB IP manually in `/etc/hosts`:

```text
192.168.100.120 home.lab.local vault.lab.local auth.lab.local n8n.lab.local code.lab.local blog.lab.local obsidian.lab.local forum.lab.local k8s.lab.local
```

Then test:

- `https://home.lab.local`
- `https://k8s.lab.local`

## Day-2 Operations

Tags: #operations #maintenance #day2

Deploy manifest changes:

```bash
kubectl apply -f manifests/apps/<app>/
kubectl rollout status deploy/<app> -n <namespace>
```

Periodic checks:

```bash
kubectl get pods -A
python3 scripts/security_scrub.py
```

Destructive teardown:

```bash
bash scripts/99-teardown.sh
```

## Common Beginner Pitfalls

Tags: #troubleshooting #pitfalls

1. `kubectl` cannot connect: check `~/.kube/config` and rerun `scripts/02-cluster-setup.sh`.
2. Workers do not join: verify `K3S_TOKEN` length and node reachability from Ansible.
3. PVCs pending: validate NFS and storage provisioner (`kubectl -n storage get pods`).
4. App starts but URL fails: check DNS/hosts and Traefik service IP.
5. App deploy fails: missing secret in the app namespace.

## Fast Rebuild Checklist

Tags: #checklist #recovery #reproducible

- [ ] Tools installed (`00-install-tools.sh`)
- [ ] Templates created (`00-create-proxmox-template.sh`)
- [ ] `terraform/terraform.tfvars` filled locally
- [ ] VMs provisioned (`01-provision.sh`)
- [ ] k3s bootstrapped (`02-cluster-setup.sh`)
- [ ] Storage/ingress configured (`03-storage-setup.sh`)
- [ ] Secrets created (`manifests/secrets/README.md`)
- [ ] Apps deployed (`04-deploy-apps.sh`)
- [ ] Health validated (`kubectl get pods -A`)
