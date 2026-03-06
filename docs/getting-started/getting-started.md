# Getting Started (k3s-cluster)

For a beginner-first, from-scratch walkthrough with ordered phases and tags, use:
- `docs/BEGINNER_JOURNEY.md`

## Prerequisites

- macOS or Linux control node
- `bash`, `git`, `python3`
- `terraform`, `ansible`, `kubectl`, `helm`
- Access to both Proxmox hosts and your TrueNAS server

## Fast Path

```bash
bash scripts/00-install-tools.sh
bash scripts/00-create-proxmox-template.sh
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
# Fill terraform/terraform.tfvars locally (do not commit)
bash scripts/01-provision.sh
export K3S_TOKEN="CHANGE_ME_MIN_20_CHARS"
bash scripts/02-cluster-setup.sh
bash scripts/03-storage-setup.sh
# Create local-only secret manifests under manifests/secrets/*.yml
# or create each secret directly with kubectl create secret ...
bash scripts/04-deploy-apps.sh

# Optional: mirror local kube contexts into Dockhand
bash scripts/05-sync-dockhand-contexts.sh
```

For Headlamp + Dockhand workflow details, see:
- `docs/DOCKHAND_HEADLAMP_WORKFLOW.md`

## Secrets Workflow

1. Keep real secrets local only.
2. Keep app manifests secret-free (no plaintext stringData values).
3. Populate runtime secrets via:
   - local-only `manifests/secrets/*.yml`, or
   - `kubectl create secret ...` before deploying.

## Validation

```bash
brew install pre-commit
pre-commit install
bash -n scripts/*.sh
pre-commit run --all-files
python3 scripts/security_scrub.py --no-history
```

Validate live manifest compatibility before apply:

```bash
kubectl apply --dry-run=server -R -f manifests/apps
```

Quick health checks after deploy:

```bash
kubectl get nodes -o wide
kubectl get pods -A
kubectl get events -A --field-selector type=Warning --sort-by=.lastTimestamp | tail -n 40
```

For a full history scan before release:

```bash
python3 scripts/security_scrub.py
```

If any finding appears, follow `docs/SECURITY_RULEBOOK.md`.

For a live production example audit and remediation log, see:
- `docs/OPERATIONS_AUDIT_2026-02-22.md`
