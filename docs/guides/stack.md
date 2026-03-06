# LABing — Full Stack Documentation

> Generated: 2026-02-22 | Cluster: k3s v1.31.4
> Latest operations audit: `docs/OPERATIONS_AUDIT_2026-02-22.md`

---

## Architecture Overview

```
Internet
    │
    ▼
Cloudflare DNS (*.smartmur.ca → 192.168.30.117)
    │
    ▼
NPM — Nginx Proxy Manager (192.168.30.117:443)
  ├── TLS termination via *.smartmur.ca Let's Encrypt wildcard (Cloudflare DNS challenge)
  └── Forwards to TrueNAS relay
    │
    ▼
TrueNAS Relay — nginx on 192.168.13.69:19200
  └── Forwards HTTPS → Traefik (192.168.100.120:443)
    │
    ▼
Traefik v2 (MetalLB VIP: 192.168.100.120)
  └── Routes by Host header to k3s pods
    │
    ├── Apps namespace (apps)
    ├── n8n namespace
    ├── discourse namespace
    ├── authentik namespace
    └── vaultwarden namespace
```

### Physical Hosts

| Host | IP | Role |
|---|---|---|
| Proxmox PVE1 | 192.168.100.100 | Hypervisor — hosts master + workers |
| Proxmox PVE2 | 192.168.100.200 | Hypervisor (expansion) |
| TrueNAS | 192.168.13.69 | NFS storage + nginx relay |
| Docker Server | 192.168.30.117 | NPM, Dockhand, misc Docker services |
| Mac (control) | via Tailscale | kubectl + SSH management |

### k3s Cluster Nodes

| Node | IP | Role | Proxmox VM |
|---|---|---|---|
| k3s-master-01 | 192.168.100.110 | control-plane | PVE1 |
| k3s-worker-01 | 192.168.100.111 | worker | PVE1 |
| k3s-worker-02 | 192.168.100.112 | worker | PVE1 |
| k3s-worker-03 | 192.168.100.113 | worker | PVE1 |

---

## Cluster Access

### kubectl (from Mac)

```bash
# Tunnel is auto-started on login via LaunchAgent
cat ~/Library/LaunchAgents/k3s-kubectl-tunnel.plist

# Manual tunnel if needed
ssh -N -L 7443:192.168.100.110:6443 root@192.168.100.100

# kubectl is pre-configured
kubectl get nodes
kubectl get pods -A
```

### SSH to Nodes

All nodes configured with Mac's ed25519 SSH key.

```bash
# ~/.ssh/config already has these entries
ssh K8-Master       # debian@192.168.100.110 (control plane)
ssh k3s-worker-01   # debian@192.168.100.111
ssh k3s-worker-02   # debian@192.168.100.112
ssh k3s-worker-03   # debian@192.168.100.113

# User: debian  |  Auth: SSH key (no password)
```

### VS Code

1. Install extensions: `ms-vscode-remote.remote-ssh` + `ms-kubernetes-tools.vscode-kubernetes-tools`
2. Remote-SSH → Connect to Host → `K8-Master`
3. Kubernetes extension auto-discovers `~/.kube/config` via tunnel

---

## Networking

### DNS

Two DNS layers:
- **Cloudflare** — authoritative for `kwe2.org` in public Internet
- **Unifi internal DNS** (192.168.13.13) — authoritative internally, does NOT forward to Cloudflare

All `*.smartmur.ca` subdomains must exist in BOTH:

| Subdomain | Cloudflare | Unifi | Points to |
|---|---|---|---|
| home.smartmur.ca | ✓ | ✓ | 192.168.30.117 (NPM) |
| vault.smartmur.ca | ✓ | ✓ | 192.168.30.117 (NPM) |
| auth.smartmur.ca | ✓ | ✓ | 192.168.30.117 (NPM) |
| n8n.smartmur.ca | ✓ | ✓ | 192.168.30.117 (NPM) |
| code.smartmur.ca | ✓ | ✓ | 192.168.30.117 (NPM) |
| obsidian.smartmur.ca | ✓ | ✓ | 192.168.30.117 (NPM) |
| blog.smartmur.ca | ✓ | ✓ | 192.168.30.117 (NPM) |
| traefik.smartmur.ca | ✓ | ✓ | 192.168.30.117 (NPM) |
| dockhand2.smartmur.ca | ✓ | ✓ | 192.168.30.117 (NPM) |
| k8s.smartmur.ca | ✓ | add manually | 192.168.30.117 (NPM) |
| pangolin.smartmur.ca | ✓ | add manually | 192.168.30.117 (NPM) |
| mail.smartmur.ca | ✓ | add manually | 192.168.30.117 (NPM) |
| forum.smartmur.ca | ✓ | add manually | 192.168.30.117 (NPM) |

> **Note**: If a new subdomain resolves externally but not internally, add it in Unifi → Network → DNS Records.

### NPM (Nginx Proxy Manager)

- **URL**: https://npm.smartmur.ca
- **Credentials**: Store in password manager only (do not document plaintext in repo)
- **Wildcard cert**: `*.smartmur.ca` (cert ID 1, via Cloudflare DNS challenge)
- All proxy hosts forward to `192.168.13.69:19200` (TrueNAS relay)

### TrueNAS Relay

Bridges Docker server subnet (192.168.30.x) to k3s subnet (192.168.100.x).

```
Config: /mnt/strange/ray/k3s-relay/nginx.conf (on TrueNAS)
PID:    /mnt/strange/ray/k3s-relay/tmp/nginx.pid
Logs:   /mnt/strange/ray/k3s-relay/logs/

# Reload after config change
ssh ray@192.168.13.69 "nginx -c /mnt/strange/ray/k3s-relay/nginx.conf -s reload"

# Persistent via crontab
@reboot /usr/sbin/nginx -c /mnt/strange/ray/k3s-relay/nginx.conf
```

### MetalLB

- Pool: `192.168.100.120–192.168.100.130`
- Traefik VIP: `192.168.100.120` (LoadBalancer service)
- Config: IPAddressPool created inline by Ansible in `ansible/playbook-nfs.yml`

---

## Storage

### StorageClasses

| Class | Provisioner | Backend | Use for |
|---|---|---|---|
| `local-path` | k3s built-in | Node local disk | Single-node apps, logs |
| `truenas-nfs` | nfs-subdir-external-provisioner | TrueNAS NFS | Shared/persistent data |

### Current App PVC StorageClass Bindings (Live)

| PVC | Namespace | StorageClass |
|---|---|---|
| `authentik-postgres-data` | authentik | `local-path` |
| `code-server-workspace` | apps | `local-path` |
| `n8n-data` | n8n | `local-path` |

> Note: these three PVCs use `local-path` in the current live cluster due immutable PVC class constraints. See `docs/OPERATIONS_AUDIT_2026-02-22.md` for remediation details and migration notes.

### TrueNAS NFS

- **Server**: 192.168.13.69
- **Export**: `/mnt/strange/NSF_Prox` (world-accessible `*`)
- **k3s subdir**: `/mnt/strange/NSF_Prox/k3s`
- **StorageClass**: `truenas-nfs`
- PVC directories auto-created under `/mnt/strange/NSF_Prox/k3s/<namespace>-<pvc-name>-<pv-id>/`

```bash
# View provisioned volumes on TrueNAS
ssh ray@192.168.13.69 "ls /mnt/strange/NSF_Prox/k3s/"
```

---

## Services

### Infrastructure Services

| Service | URL | Notes |
|---|---|---|
| Traefik Dashboard | https://traefik.smartmur.ca/dashboard/ | No auth (internal only) |
| NPM | https://npm.smartmur.ca | See credentials above |
| Authentik | https://auth.smartmur.ca | SSO provider |
| Vaultwarden | https://vault.smartmur.ca | Password manager |
| Dockhand | https://dockhand2.smartmur.ca | Docker/Hawser management (not native Kubernetes API) |
| Headlamp | https://k8s.smartmur.ca | Native Kubernetes web manager |
| Pangolin | https://pangolin.smartmur.ca | WireGuard tunneled proxy |

### Application Services

| Service | URL | Notes |
|---|---|---|
| Homepage | https://home.smartmur.ca | Dashboard, no auth |
| n8n | https://n8n.smartmur.ca | Workflow automation |
| Code Server | https://code.smartmur.ca | Browser IDE |
| Obsidian | https://obsidian.smartmur.ca | Knowledge base (KasmVNC) |
| Chirpy Blog | https://blog.smartmur.ca | Jekyll blog |
| Discourse | https://forum.smartmur.ca | Forum (offline — see below) |
| Mailhog | https://mail.smartmur.ca | SMTP catch-all (dev use) |

---

## Credentials

| App | Username | Password / Token | Notes |
|---|---|---|---|
| **Code Server** | — | `CHANGE_ME_CODE_SERVER_PASSWORD` | Set in k8s secret |
| **n8n** | Set on first visit | Set on first visit | First-run wizard |
| **Dockhand** | Set on first visit | Set on first visit | First-run wizard |
| **Headlamp** | — | — | In-cluster service account; currently exposed without app auth |
| **Portainer** → replaced by Dockhand | — | — | — |
| **Authentik** | Set on first visit | Set on first visit | Go to `/if/flow/initial-setup/` |
| **Vaultwarden** | Self-register | Self-register | Admin at `/admin` |
| **Vaultwarden Admin** | — | `CHANGE_ME_VAULTWARDEN_ADMIN_TOKEN` | Set in k8s secret |
| **Pangolin** | Set on first visit | Set on first visit | First-run |
| **Obsidian** | — | No password | KasmVNC desktop |
| **Homepage / Blog** | — | — | Public, no auth |
| **Mailhog** | — | — | Public, no auth |

> **Security note**: `vaultwarden-secret` in namespace `vaultwarden` contains the ADMIN_TOKEN. Rotate with:
> ```bash
> kubectl create secret generic vaultwarden-secret -n vaultwarden \
>   --from-literal=ADMIN_TOKEN='new_token' \
>   --from-literal=DOMAIN='https://vault.smartmur.ca' \
>   --dry-run=client -o yaml | kubectl apply -f -
> ```

---

## Manifest Directory Structure

```
/Users/dre/k3s-cluster/
├── manifests/
│   ├── namespaces.yml              # All namespace definitions
│   ├── ingress/
│   │   ├── (MetalLB pool — created inline by ansible/playbook-nfs.yml)
│   │   ├── traefik-defaults.yml    # TLS store, HTTP→HTTPS redirect, security headers
│   │   └── traefik-dashboard.yml   # Traefik dashboard IngressRoute
│   ├── storage/
│   │   └── (nfs provisioner via Helm)
│   └── apps/
│       ├── authentik/authentik.yml
│       ├── chirpy/chirpy.yml
│       ├── code-server/code-server.yml
│       ├── discourse/discourse.yml   # Postgres + Redis running; web scaled=0
│       ├── dockhand/dockhand.yml     # fnsys/dockhand
│       ├── headlamp/headlamp.yml     # Kubernetes web UI
│       ├── homepage/homepage.yml
│       ├── n8n/n8n.yml
│       ├── obsidian/obsidian.yml
│       ├── pangolin/pangolin.yml     # WireGuard tunneled proxy
│       └── vaultwarden/vaultwarden.yml
└── STACK.md                          # This file
```

---

## How to Deploy a New App

1. **Create manifest** in `/Users/dre/k3s-cluster/manifests/apps/<appname>/`:

```yaml
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
  namespace: apps
spec:
  replicas: 1
  selector:
    matchLabels:
      app: myapp
  template:
    metadata:
      labels:
        app: myapp
    spec:
      containers:
        - name: myapp
          image: myimage:latest
          ports:
            - containerPort: 3000
---
apiVersion: v1
kind: Service
metadata:
  name: myapp
  namespace: apps
spec:
  selector:
    app: myapp
  ports:
    - port: 3000
---
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: myapp
  namespace: apps
spec:
  entryPoints: [websecure]
  routes:
    - match: Host(`myapp.smartmur.ca`)
      kind: Rule
      services:
        - name: myapp
          port: 3000
  tls: {}
```

2. **Apply**: `kubectl apply -f manifests/apps/myapp/myapp.yml`

3. **Add NPM proxy host** via https://npm.smartmur.ca:
   - Domain: `myapp.smartmur.ca`
   - Forward: `192.168.13.69:19200`
   - Certificate: `*.smartmur.ca` (ID 1)
   - Enable WebSocket if needed

4. **Add DNS records**:
   - Cloudflare: A record `myapp.smartmur.ca → 192.168.30.117`
   - Unifi DNS: A record `myapp.smartmur.ca → 192.168.30.117`

---

## Discourse — Deployment Notes

Discourse web is **scaled to 0** because the official image requires bootstrapping.

The database (PostgreSQL on TrueNAS NFS) and Redis are running.

**To bring Discourse online**:

```bash
# Option A — Use official Discourse launcher on Docker server (recommended)
# SSH to ray@192.168.30.117 and follow:
# https://github.com/discourse/discourse/blob/main/docs/INSTALL-cloud.md

# Option B — Bootstrap the k8s Discourse deployment
kubectl scale deployment discourse -n discourse --replicas=1
# Watch logs:
kubectl logs -n discourse deployment/discourse -f
# Admin: CHANGE_ME_DISCOURSE_ADMIN_EMAIL / CHANGE_ME_DISCOURSE_ADMIN_PASSWORD
# Emails captured by Mailhog at https://mail.smartmur.ca
```

---

## Chirpy Blog — Content Management

The blog is built from a Jekyll ConfigMap using the Chirpy theme.

**To add/edit posts**:
1. Edit the `chirpy-site` ConfigMap in `/Users/dre/k3s-cluster/manifests/apps/chirpy/chirpy.yml`
2. Add post content under the `data:` section as `postname.md:`
3. Apply and restart:
   ```bash
   kubectl apply -f manifests/apps/chirpy/chirpy.yml
   kubectl rollout restart deployment/chirpy -n apps
   ```

**Jekyll build runs on every pod restart** (init container).

---

## Troubleshooting

### App returns 502/503

1. Check pod is running: `kubectl get pods -n <namespace>`
2. Check TrueNAS relay: `ssh ray@192.168.13.69 "nginx -c /mnt/strange/ray/k3s-relay/nginx.conf -t"`
3. Check Traefik routing: https://traefik.smartmur.ca/dashboard/#/http/routers
4. Check NPM proxy host is pointing to `192.168.13.69:19200`

### App DNS not resolving

- External: Check Cloudflare DNS record exists and is NOT proxied (orange cloud = problem)
- Internal: Add A record in Unifi → Network → DNS → Local Records
- Mac cache: `sudo dscacheutil -flushcache && sudo killall -HUP mDNSResponder`

### Pod stuck in ContainerCreating

```bash
kubectl describe pod <podname> -n <namespace>
# Common causes:
# - NFS mount failing: check TrueNAS /mnt/strange/NSF_Prox/k3s/ exists
# - Docker socket missing: don't use hostPath docker.sock on k3s (containerd)
# - ConfigMap not found
```

### Pod OOMKilled

```bash
kubectl describe pod <podname> -n <namespace> | grep -A5 "Last State"
# Increase memory limits in the manifest
```

### WebSocket apps appear broken (n8n, obsidian, code-server)

The TrueNAS nginx relay handles WebSocket upgrade. Verify:
```bash
ssh ray@192.168.13.69 "cat /mnt/strange/ray/k3s-relay/nginx.conf | grep connection_upgrade"
# Should show: map $http_upgrade $connection_upgrade block
```

### kubectl not connecting

Check the SSH tunnel is running:
```bash
ps aux | grep "ssh.*7443"
# If not running, reload the LaunchAgent:
launchctl load ~/Library/LaunchAgents/k3s-kubectl-tunnel.plist
```

---

## NFS Provisioner Management

```bash
# Check provisioner
kubectl get pods -n storage

# List provisioned volumes
kubectl get pv | grep truenas-nfs

# Helm upgrade (if NFS path changes)
kubectl delete storageclass truenas-nfs
helm upgrade nfs-provisioner nfs-subdir-external-provisioner \
  --repo https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner \
  --namespace storage \
  --set nfs.server=192.168.13.69 \
  --set nfs.path=/mnt/strange/NSF_Prox/k3s \
  --set storageClass.name=truenas-nfs
```

---

## Secrets Reference

All secrets are stored in Kubernetes and can be viewed with:

```bash
kubectl get secret <name> -n <namespace> -o jsonpath='{.data}' | \
  python3 -c "import sys,json,base64; [print(k,':', base64.b64decode(v).decode()) for k,v in json.load(sys.stdin).items()]"
```

| Secret Name | Namespace | Contains |
|---|---|---|
| `vaultwarden-secret` | vaultwarden | ADMIN_TOKEN, DOMAIN |
| `n8n-secret` | n8n | DB_TYPE, N8N_ENCRYPTION_KEY, WEBHOOK_URL |
| `code-server-secret` | apps | PASSWORD |
| `authentik-secret` | authentik | AUTHENTIK_SECRET_KEY, AUTHENTIK_POSTGRESQL_PASSWORD |
| `discourse-secret` | discourse | POSTGRESQL_PASSWORD, DISCOURSE_PASSWORD, DISCOURSE_EMAIL |

---

## Key Infrastructure IPs

| Resource | IP | Notes |
|---|---|---|
| Traefik VIP | 192.168.100.120 | MetalLB LoadBalancer |
| k3s Master | 192.168.100.110 | API server, etcd |
| k3s Worker 01 | 192.168.100.111 | |
| k3s Worker 02 | 192.168.100.112 | |
| k3s Worker 03 | 192.168.100.113 | |
| Proxmox PVE1 | 192.168.100.100 | Main hypervisor |
| Proxmox PVE2 | 192.168.100.200 | Secondary hypervisor |
| TrueNAS | 192.168.13.69 | Storage + relay |
| Docker Server | 192.168.30.117 | NPM + Docker |
| Unifi (DNS/FW) | 192.168.13.13 | Internal DNS authority |
| murzpi (Tailscale) | 192.168.13.83 | Routes all subnets via Tailscale |

---

*Documentation auto-generated from live cluster state - 2026-02-22*
