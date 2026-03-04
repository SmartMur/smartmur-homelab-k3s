# Local Secrets Overlay

Use this directory for local-only secret manifests if you need file-based secret deployment.

- Files in this folder are ignored by `.gitignore`.
- Keep `.gitkeep` only in version control.
- Prefer `kubectl create secret ... --dry-run=client -o yaml | kubectl apply -f -` to avoid writing plaintext to disk.

Example:

```bash
kubectl create secret generic code-server-secret -n apps \
  --from-literal=PASSWORD='CHANGE_ME' \
  --dry-run=client -o yaml | kubectl apply -f -
```

Required runtime secrets by app:

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
