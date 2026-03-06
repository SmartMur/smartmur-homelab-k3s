# Secret Rotation Schedule

Last updated: 2026-02-28

Rotation procedures and schedule for all secrets in the k3s cluster.

## 1. Secret Inventory

| Secret | Namespace | Key(s) | Rotation Cadence | Method |
|---|---|---|---|---|
| `proxmox_api_token` | — (Terraform) | `proxmox_api_token` | 90 days | Proxmox UI + tfvars |
| `k3s_token` | — (Ansible / env) | `K3S_TOKEN` | 180 days | Ansible re-deploy |
| `vaultwarden-secret` | vaultwarden | `ADMIN_TOKEN` | 90 days | kubectl re-create |
| `authentik-secret` | authentik | `AUTHENTIK_SECRET_KEY`, `POSTGRES_PASSWORD` | 90 days | kubectl re-create + pod restart |
| `n8n-secret` | n8n | `N8N_ENCRYPTION_KEY`, `N8N_USER_MANAGEMENT_JWT_SECRET` | 180 days | kubectl re-create + pod restart |
| `code-server-secret` | apps | `PASSWORD` | 180 days | kubectl re-create + pod restart |
| `pangolin-secret` | apps | `PANGOLIN_APP_SECRET` | 180 days | kubectl re-create + pod restart |
| `discourse-secret` | discourse | `POSTGRESQL_PASSWORD`, `DISCOURSE_PASSWORD` | 90 days | kubectl re-create + pod restart |
| `notify-channel-secrets` | apps | `TELEGRAM_BOT_TOKEN`, `TWILIO_AUTH_TOKEN`, SMTP creds | 90 days | kubectl re-create + pod restart |
| SSH keys (ed25519) | — (all nodes) | `~/.ssh/id_ed25519` | 365 days | Key regen + Ansible push |
| NPM admin password | — (Docker host) | Web UI login | 90 days | NPM web UI |
| Cloudflare API token | — (NPM DNS challenge) | Let's Encrypt DNS-01 | 180 days | Cloudflare dashboard + NPM |

## 2. Rotation Procedures

### 2.1 Proxmox API Token

```bash
# 1. Generate new token in Proxmox UI:
#    Datacenter → Permissions → API Tokens → Add
#    User: root@pam (or dedicated service account)

# 2. Update local tfvars (never committed)
vim terraform/terraform.tfvars
# Set: proxmox_api_token = "PVEAPIToken=user@pam!tokenid=NEW_SECRET"

# 3. Validate
cd terraform && terraform plan

# 4. Revoke old token in Proxmox UI
```

### 2.2 k3s Cluster Token

The k3s token authenticates worker nodes to the control plane. Rotation requires rejoining all workers.

```bash
# 1. Generate new token
NEW_TOKEN=$(openssl rand -hex 32)

# 2. On master node — update the token file
ssh K8-Master "sudo k3s token rotate --new-token ${NEW_TOKEN}"

# 3. On each worker — rejoin with new token
for w in k3s-worker-01 k3s-worker-02 k3s-worker-03; do
  ssh $w "sudo systemctl stop k3s-agent"
  ssh $w "sudo sed -i \"s|^K3S_TOKEN=.*|K3S_TOKEN=${NEW_TOKEN}|\" /etc/systemd/system/k3s-agent.service.env"
  ssh $w "sudo systemctl daemon-reload && sudo systemctl start k3s-agent"
done

# 4. Update local env for future Ansible runs
export K3S_TOKEN="${NEW_TOKEN}"
# Store in password manager

# 5. Verify all nodes rejoin
kubectl get nodes
```

### 2.3 App-Level Kubernetes Secrets

All app secrets follow the same pattern: re-create the secret, then restart the deployment.

```bash
# Generic rotation template
kubectl create secret generic <SECRET_NAME> -n <NAMESPACE> \
  --from-literal=KEY1='NEW_VALUE_1' \
  --from-literal=KEY2='NEW_VALUE_2' \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl rollout restart deployment/<DEPLOYMENT> -n <NAMESPACE>
kubectl rollout status deployment/<DEPLOYMENT> -n <NAMESPACE>
```

**Vaultwarden**

```bash
NEW_ADMIN=$(openssl rand -hex 32)

kubectl create secret generic vaultwarden-secret -n vaultwarden \
  --from-literal=ADMIN_TOKEN="${NEW_ADMIN}" \
  --from-literal=DOMAIN='https://vault.smartmur.ca' \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl rollout restart deployment/vaultwarden -n vaultwarden
```

**Authentik**

```bash
NEW_SECRET_KEY=$(openssl rand -hex 50)
NEW_PG_PASS=$(openssl rand -hex 24)

# WARNING: Changing POSTGRES_PASSWORD requires updating the PG database user too.
# If only rotating the app secret key, keep the existing PG password.

kubectl create secret generic authentik-secret -n authentik \
  --from-literal=AUTHENTIK_SECRET_KEY="${NEW_SECRET_KEY}" \
  --from-literal=POSTGRES_DB='authentik' \
  --from-literal=POSTGRES_USER='authentik' \
  --from-literal=POSTGRES_PASSWORD="${NEW_PG_PASS}" \
  --dry-run=client -o yaml | kubectl apply -f -

# If PG password changed, update the database role BEFORE restarting:
kubectl exec -n authentik deploy/authentik-postgres -- \
  psql -U authentik -c "ALTER ROLE authentik WITH PASSWORD '${NEW_PG_PASS}';"

kubectl rollout restart deployment/authentik-server -n authentik
kubectl rollout restart deployment/authentik-worker -n authentik
```

**n8n**

```bash
# CAUTION: Rotating N8N_ENCRYPTION_KEY will make existing encrypted
# credentials unreadable. Export credentials first if needed.

NEW_JWT=$(openssl rand -hex 32)

kubectl create secret generic n8n-secret -n n8n \
  --from-literal=DB_TYPE='sqlite' \
  --from-literal=N8N_ENCRYPTION_KEY='KEEP_EXISTING_UNLESS_COMPROMISED' \
  --from-literal=N8N_USER_MANAGEMENT_JWT_SECRET="${NEW_JWT}" \
  --from-literal=WEBHOOK_URL='https://n8n.smartmur.ca' \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl rollout restart deployment/n8n -n n8n
```

**Notification Channel Secrets (Telegram, Twilio, SMTP)**

```bash
# Rotate individual provider credentials as needed.
# Regenerate Telegram bot token via @BotFather.
# Regenerate Twilio auth token via Twilio Console.
# Regenerate SMTP app password via email provider.

kubectl create secret generic notify-channel-secrets -n apps \
  --from-literal=TELEGRAM_BOT_TOKEN='...' \
  --from-literal=TELEGRAM_CHAT_ID='...' \
  --from-literal=TWILIO_ACCOUNT_SID='...' \
  --from-literal=TWILIO_AUTH_TOKEN='...' \
  --from-literal=TWILIO_WHATSAPP_FROM='whatsapp:+14155238886' \
  --from-literal=TWILIO_WHATSAPP_TO='whatsapp:+10000000000' \
  --from-literal=ALERT_SMTP_HOST='smtp.gmail.com' \
  --from-literal=ALERT_SMTP_PORT='587' \
  --from-literal=ALERT_EMAIL_USER='...' \
  --from-literal=ALERT_EMAIL_PASSWORD='...' \
  --from-literal=ALERT_FROM_EMAIL='notify@kwe2.org' \
  --from-literal=ALERT_TO_EMAIL_1='you@example.com' \
  --dry-run=client -o yaml | kubectl apply -f -

# Restart any pods that consume this secret
```

**Code Server / Pangolin / Discourse**

```bash
# Code Server
kubectl create secret generic code-server-secret -n apps \
  --from-literal=PASSWORD="$(openssl rand -base64 24)" \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl rollout restart deployment/code-server -n apps

# Pangolin
kubectl create secret generic pangolin-secret -n apps \
  --from-literal=PANGOLIN_APP_SECRET="$(openssl rand -hex 32)" \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl rollout restart deployment/pangolin -n apps

# Discourse (PG password + admin password)
kubectl create secret generic discourse-secret -n discourse \
  --from-literal=POSTGRESQL_PASSWORD="$(openssl rand -hex 24)" \
  --from-literal=DISCOURSE_EMAIL='admin@example.com' \
  --from-literal=DISCOURSE_PASSWORD="$(openssl rand -base64 24)" \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl rollout restart deployment/discourse -n discourse
```

### 2.4 SSH Keys

```bash
# 1. Generate new key pair on Mac
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_new -C "dre@lab-$(date +%Y%m)"

# 2. Push new public key to all nodes (while old key still works)
for host in K8-Master k3s-worker-01 k3s-worker-02 k3s-worker-03; do
  ssh-copy-id -i ~/.ssh/id_ed25519_new.pub $host
done

# 3. Also push to Proxmox and TrueNAS
ssh-copy-id -i ~/.ssh/id_ed25519_new.pub root@192.168.100.100
ssh-copy-id -i ~/.ssh/id_ed25519_new.pub ray@192.168.13.69

# 4. Test new key on all hosts
for host in K8-Master k3s-worker-01 k3s-worker-02 k3s-worker-03; do
  ssh -i ~/.ssh/id_ed25519_new $host "hostname"
done

# 5. Swap into place
mv ~/.ssh/id_ed25519 ~/.ssh/id_ed25519_old
mv ~/.ssh/id_ed25519.pub ~/.ssh/id_ed25519_old.pub
mv ~/.ssh/id_ed25519_new ~/.ssh/id_ed25519
mv ~/.ssh/id_ed25519_new.pub ~/.ssh/id_ed25519.pub

# 6. Update terraform.tfvars with new public key
# 7. Remove old key from all hosts after confirming new key works

# 8. Remove old authorized key from nodes
OLD_KEY_FINGERPRINT=$(ssh-keygen -lf ~/.ssh/id_ed25519_old.pub | awk '{print $2}')
echo "Remove entries matching: ${OLD_KEY_FINGERPRINT}"
```

## 3. Post-Rotation Validation

Run these checks after rotating each secret category.

| Secret Rotated | Validation Command | Expected Result |
|---|---|---|
| Proxmox API token | `cd terraform && terraform plan` | Plan succeeds, no auth errors |
| k3s token | `kubectl get nodes` | All nodes `Ready` |
| Vaultwarden | `curl -sf https://vault.smartmur.ca/alive` | HTTP 200 |
| Authentik | `curl -sf https://auth.smartmur.ca/-/health/live/` | HTTP 200 |
| n8n | `curl -sf https://n8n.smartmur.ca/healthz` | HTTP 200 |
| Code Server | `curl -sf -o /dev/null -w '%{http_code}' https://code.smartmur.ca` | HTTP 200/302 |
| Pangolin | `curl -sf -o /dev/null -w '%{http_code}' https://pangolin.smartmur.ca` | HTTP 200/302 |
| Discourse | `kubectl logs -n discourse deploy/discourse --tail=20` | No crash loops |
| Notify channels | Trigger a test alert via n8n or monitoring | Alert arrives on Telegram/email |
| SSH keys | `ssh K8-Master hostname` | Returns hostname |
| NPM admin | Log in at https://npm.smartmur.ca | Login succeeds |
| Cloudflare token | Check cert renewal: NPM SSL → `*.smartmur.ca` expiry date | Cert valid |

Full cluster health check after any rotation:

```bash
kubectl get nodes
kubectl get pods -A | grep -v Running | grep -v Completed
kubectl get events -A --sort-by='.lastTimestamp' | tail -20
```

## 4. Rotation Schedule

| Cadence | Secrets | Next Due |
|---|---|---|
| **90 days** | Proxmox API token, Vaultwarden admin token, Authentik secret key, Discourse passwords, Notify channel credentials (Telegram/Twilio/SMTP), NPM admin password | 2026-05-29 |
| **180 days** | k3s cluster token, n8n JWT secret, Code Server password, Pangolin app secret, Cloudflare API token | 2026-08-27 |
| **365 days** | SSH keys | 2027-02-28 |
| **On compromise** | Any secret — immediately rotate, follow [Security Incident Playbook](SECURITY_RULEBOOK.md#4-security-incident-playbook) | — |

### Rotation Checklist (run quarterly)

```
[ ] Proxmox API token rotated
[ ] Vaultwarden admin token rotated
[ ] Authentik secret key rotated
[ ] Discourse DB + admin passwords rotated
[ ] Notify channel secrets reviewed and rotated
[ ] NPM admin password rotated
[ ] All pods healthy after rotation (kubectl get pods -A)
[ ] Updated "Next Due" dates in this document
[ ] Stored new credentials in password manager
```
