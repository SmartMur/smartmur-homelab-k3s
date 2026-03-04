# Dockhand Context Sync + Headlamp

This repo now includes two complementary management paths:

1. `Headlamp` for native Kubernetes management
2. `Dockhand` context tracking sync from local `kubectl` contexts

## What Was Added

- New app manifest: `manifests/apps/headlamp/headlamp.yml`
- Homepage integration: `manifests/apps/homepage/homepage.yml`
  - Adds Headlamp card (`https://k8s.smartmur.ca`)
  - Keeps Dockhand card and clarifies Dockhand scope
- New automation script: `scripts/05-sync-dockhand-contexts.sh`
  - Idempotently creates/updates Dockhand environments named `k8s-<context>`

## Deploy / Apply

```bash
kubectl apply -f manifests/apps/headlamp/
kubectl apply -f manifests/apps/homepage/
bash scripts/05-sync-dockhand-contexts.sh
```

## Verify

```bash
kubectl -n apps get deploy headlamp homepage dockhand
kubectl -n apps get svc headlamp homepage dockhand
kubectl -n apps get ingressroute headlamp homepage dockhand
```

Check from Dockhand DB (in-cluster):

```bash
kubectl -n apps exec deploy/dockhand -- \
  sqlite3 /app/data/db/dockhand.db \
  "select id,name,connection_type,labels from environments where name like 'k8s-%' order by id;"
```

## DNS / Edge Routing Requirements

For `https://k8s.smartmur.ca` to be reachable end-to-end:

1. Cloudflare `A` record: `k8s.smartmur.ca -> 192.168.30.117`
2. Unifi local DNS `A` record: `k8s.smartmur.ca -> 192.168.30.117`
3. NPM proxy host for `k8s.smartmur.ca` forwarding to `192.168.13.69:19200`
4. Use wildcard TLS certificate `*.smartmur.ca`

## Security Notes

- Headlamp is currently bound with `cluster-admin` via service account.
- Keep Headlamp internal-only unless you front it with SSO (Authentik) and IP restrictions.
- `scripts/05-sync-dockhand-contexts.sh` does not expose Kubernetes APIs through Dockhand; it registers context-tracking environments in Dockhand using `hawser-edge` profile defaults.

## Re-run Strategy

Re-run after kubeconfig context changes:

```bash
bash scripts/05-sync-dockhand-contexts.sh
```

The script is safe to run repeatedly; existing `k8s-*` environments are updated in place.
