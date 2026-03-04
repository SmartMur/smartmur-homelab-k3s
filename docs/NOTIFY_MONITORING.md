# Notify Monitoring on k3s

This runbook deploys `Notify` into the `apps` namespace and adds it to Homepage.

## What gets deployed

- `Deployment` `notify` (apps namespace)
- `Service` `notify` on port `9090`
- `IngressRoute` `notify` at `https://notify.smartmur.ca`
- `ServiceAccount` + read-only `ClusterRole` + `ClusterRoleBinding`
- namespaced restart `Role` + `RoleBinding` for allowlisted deployments
- `PersistentVolumeClaim` `notify-data` for alert state persistence
- ConfigMap `notify-config` (runtime monitoring config)
- ConfigMap `notify-app-code` (app source injected at deploy time)

## Deploy

```bash
cd /Users/dre/k3s-cluster
bash scripts/deploy-notify.sh /Users/dre/Desktop/LABing/Projects/Notify
```

If you omit the argument, the script defaults to `/Users/dre/Desktop/LABing/Projects/Notify`.

## Verify

```bash
kubectl -n apps get deploy notify
kubectl -n apps get pods -l app=notify
kubectl -n apps logs deploy/notify --tail=100
kubectl -n apps get svc notify
kubectl -n apps get ingressroute notify
```

Health endpoints:

- `https://notify.smartmur.ca/` (web dashboard UI)
- `https://notify.smartmur.ca/status` (JSON status payload)
- `https://notify.smartmur.ca/readyz` (service readiness)
- `https://notify.smartmur.ca/healthz` (strict health, returns `503` when checks fail)

`k8s_pods` behavior note:

- `max_container_restarts` is evaluated together with `recent_restart_window_minutes`.
- A pod is only flagged for restart count when the latest restart is inside that time window.
- Current default window: `360` minutes (6 hours).

## Homepage integration

`manifests/apps/homepage/homepage.yml` includes a Notify card in the `Apps` section:

- href: `https://notify.smartmur.ca`
- monitor: `http://notify:9090/readyz`

## Secure channel credentials

Notify reads channel credentials from secret `notify-channel-secrets` in namespace `apps`.

Create/update it without writing plaintext to git:

```bash
kubectl create secret generic notify-channel-secrets -n apps \
  --from-literal=TELEGRAM_BOT_TOKEN='REPLACE_ME' \
  --from-literal=TELEGRAM_CHAT_ID='REPLACE_ME' \
  --from-literal=TWILIO_ACCOUNT_SID='REPLACE_ME' \
  --from-literal=TWILIO_AUTH_TOKEN='REPLACE_ME' \
  --from-literal=TWILIO_WHATSAPP_FROM='whatsapp:+14155238886' \
  --from-literal=TWILIO_WHATSAPP_TO='whatsapp:+10000000000' \
  --from-literal=ALERT_SMTP_HOST='smtp.gmail.com' \
  --from-literal=ALERT_SMTP_PORT='587' \
  --from-literal=ALERT_EMAIL_USER='REPLACE_ME' \
  --from-literal=ALERT_EMAIL_PASSWORD='REPLACE_ME' \
  --from-literal=ALERT_FROM_EMAIL='notify@kwe2.org' \
  --from-literal=ALERT_TO_EMAIL_1='you@example.com' \
  --dry-run=client -o yaml | kubectl apply -f -
```

After updating secret values, restart Notify:

```bash
kubectl -n apps rollout restart deployment/notify
kubectl -n apps rollout status deployment/notify --timeout=300s
```

Telegram note:

- `TELEGRAM_BOT_TOKEN` alone is not enough.
- The destination user/group must send at least one message (for example `/start`) to the bot first.
- Then read `message.chat.id` from:

```bash
curl -sS "https://api.telegram.org/bot<TELEGRAM_BOT_TOKEN>/getUpdates?limit=10"
```

## Enable channels

Channels are disabled by default in `manifests/apps/notify/notify.yml`.
Enable whichever you want by changing `enabled: false` to `enabled: true` under:

- `channels.telegram`
- `channels.whatsapp`
- `channels.email`

Then re-apply Notify:

```bash
kubectl apply -f manifests/apps/notify/
kubectl -n apps rollout restart deployment/notify
```

## Telegram ChatOps

`Notify` can process Telegram commands when `chatops.telegram.enabled=true`.

Supported commands:

- `/status`
- `/diag <check_id>`
- `/restart [namespace/]deployment`
- `/help`

Controls:

- only `admin_chat_ids` can execute commands
- restart command is restricted by:
  - `chatops.telegram.restart.allowed_namespaces`
  - `chatops.telegram.restart.allowed_deployments`
- command history is written to Notify local state (`chatops.telegram.audit`)

### Telegram Ops Cheat Sheet

Quick commands:

- `/help`
- `/status`
- `/diag <check_id>`
- `/restart [namespace/]deployment`

Common check IDs in this stack:

- `k8s_nodes`
- `k8s_pods`
- `k8s_deployments`
- `k8s_dashboard_http`
- `obsidian_http`
- `homepage_http`

Obsidian recovery flow:

1. `/diag obsidian_http`
2. `/restart apps/obsidian`
3. wait 30-60 seconds
4. `/diag obsidian_http`
5. `/status`
