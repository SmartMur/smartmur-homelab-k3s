#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# 04-deploy-apps.sh — Deploy all apps to k3s
# IMPORTANT: Create runtime secrets first (manifests/secrets/*.yml or kubectl).
# ──────────────────────────────────────────────────────────────────────────────
set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
log()  { echo -e "${GREEN}[✓]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
die()  { echo -e "${RED}[✗]${NC} $*"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MANIFESTS_DIR="$SCRIPT_DIR/../manifests"

command -v kubectl &>/dev/null || die "kubectl not found."
kubectl cluster-info &>/dev/null   || die "Cannot reach k3s cluster."

# ── Check for un-replaced placeholders in tracked manifests ──────────────────
CHANGE_ME_HITS="$(grep -R --include='*.yml' --exclude-dir='secrets' 'CHANGE_ME' "$MANIFESTS_DIR" 2>/dev/null || true)"
CHANGE_ME_COUNT="$(printf '%s\n' "$CHANGE_ME_HITS" | sed '/^$/d' | wc -l | tr -d ' ')"
if [[ "$CHANGE_ME_COUNT" -gt 0 ]]; then
  warn "Found $CHANGE_ME_COUNT CHANGE_ME placeholders in tracked manifests."
  printf '%s\n' "$CHANGE_ME_HITS"
  echo ""
  read -rp "Continue anyway? (yes/no): " confirm
  [[ "$confirm" == "yes" ]] || exit 0
fi

# ── Create namespaces ────────────────────────────────────────────────────────
log "Applying namespaces..."
kubectl apply -f "$MANIFESTS_DIR/namespaces.yml"

# ── Apply local secrets overlays (optional) ──────────────────────────────────
if compgen -G "$MANIFESTS_DIR/secrets/*.yml" > /dev/null; then
  log "Applying local secrets overlays..."
  kubectl apply -f "$MANIFESTS_DIR/secrets/"
else
  warn "No local secrets found at $MANIFESTS_DIR/secrets/*.yml"
fi

# ── Apply ingress config ──────────────────────────────────────────────────────
log "Applying Traefik defaults..."
kubectl apply -f "$MANIFESTS_DIR/ingress/"

# ── Deploy apps ───────────────────────────────────────────────────────────────
APPS=(homepage chirpy vaultwarden authentik n8n code-server obsidian discourse dockhand headlamp pangolin)

for app in "${APPS[@]}"; do
  if [[ -d "$MANIFESTS_DIR/apps/$app" ]]; then
    log "Deploying $app..."
    kubectl apply -f "$MANIFESTS_DIR/apps/$app/"
  else
    warn "Skipping $app — manifests not found at $MANIFESTS_DIR/apps/$app/"
  fi
done

# ── Deploy Notify monitor (requires source project path) ────────────────────
if [[ -x "$SCRIPT_DIR/deploy-notify.sh" ]]; then
  if [[ -d "/Users/dre/Desktop/LABing/Projects/Notify" ]]; then
    log "Deploying notify..."
    "$SCRIPT_DIR/deploy-notify.sh" "/Users/dre/Desktop/LABing/Projects/Notify" || \
      warn "Notify deploy script failed (non-fatal)."
  else
    warn "Notify source not found at /Users/dre/Desktop/LABing/Projects/Notify"
  fi
fi

# ── Wait for rollout ──────────────────────────────────────────────────────────
log "Waiting for deployments to be ready (up to 5 minutes)..."
declare -A NS_MAP=(
  [homepage]=apps [chirpy]=apps [code-server]=apps
  [obsidian]=apps [dockhand]=apps [headlamp]=apps [notify]=apps
  [vaultwarden]=vaultwarden [n8n]=n8n
)

for app in "${!NS_MAP[@]}"; do
  ns="${NS_MAP[$app]}"
  kubectl rollout status deployment/"$app" -n "$ns" --timeout=300s 2>/dev/null && \
    log "$app — Ready" || warn "$app — timeout (check: kubectl get pods -n $ns)"
done

# ── Sync Dockhand environments from local kube contexts (best-effort) ───────
if [[ -x "$SCRIPT_DIR/05-sync-dockhand-contexts.sh" ]]; then
  log "Syncing Dockhand environments from kubectl contexts..."
  "$SCRIPT_DIR/05-sync-dockhand-contexts.sh" || \
    warn "Dockhand context sync failed (non-fatal). Run scripts/05-sync-dockhand-contexts.sh manually."
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
log "All apps deployed. Service URLs (add to /etc/hosts or DNS):"
echo ""
TRAEFIK_IP=$(kubectl get svc traefik -n traefik -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "192.168.100.120")
printf "  %-35s %s\n" "https://home.lab.local"     "$TRAEFIK_IP  home.lab.local"
printf "  %-35s %s\n" "https://vault.lab.local"    "$TRAEFIK_IP  vault.lab.local"
printf "  %-35s %s\n" "https://auth.lab.local"     "$TRAEFIK_IP  auth.lab.local"
printf "  %-35s %s\n" "https://n8n.lab.local"      "$TRAEFIK_IP  n8n.lab.local"
printf "  %-35s %s\n" "https://code.lab.local"     "$TRAEFIK_IP  code.lab.local"
printf "  %-35s %s\n" "https://blog.lab.local"     "$TRAEFIK_IP  blog.lab.local"
printf "  %-35s %s\n" "https://obsidian.lab.local" "$TRAEFIK_IP  obsidian.lab.local"
printf "  %-35s %s\n" "https://forum.lab.local"    "$TRAEFIK_IP  forum.lab.local"
printf "  %-35s %s\n" "https://k8s.lab.local"      "$TRAEFIK_IP  k8s.lab.local"
echo ""
log "Done!"
