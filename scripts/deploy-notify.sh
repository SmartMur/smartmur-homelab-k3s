#!/usr/bin/env bash
# Deploy Notify into k3s using source from LABing/Projects/Notify.
set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
log()  { echo -e "${GREEN}[notify]${NC} $*"; }
warn() { echo -e "${YELLOW}[notify]${NC} $*"; }
die()  { echo -e "${RED}[notify]${NC} $*"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
MANIFEST_DIR="${REPO_ROOT}/manifests/apps/notify"
SOURCE_DIR="${1:-/Users/dre/Desktop/LABing/Projects/Notify}"

command -v kubectl >/dev/null 2>&1 || die "kubectl is required"
kubectl cluster-info >/dev/null 2>&1 || die "cannot reach k3s cluster"

[[ -d "${MANIFEST_DIR}" ]] || die "missing manifest dir: ${MANIFEST_DIR}"
[[ -d "${SOURCE_DIR}/notify" ]] || die "missing notify source dir: ${SOURCE_DIR}/notify"

for f in __init__.py __main__.py channels.py checks.py config.py engine.py state.py types.py; do
  [[ -f "${SOURCE_DIR}/notify/${f}" ]] || die "missing source file: ${SOURCE_DIR}/notify/${f}"
done

log "Applying namespace baseline"
kubectl apply -f "${REPO_ROOT}/manifests/namespaces.yml" >/dev/null

log "Creating/refreshing notify app code ConfigMap"
kubectl -n apps create configmap notify-app-code \
  --from-file=__init__.py="${SOURCE_DIR}/notify/__init__.py" \
  --from-file=__main__.py="${SOURCE_DIR}/notify/__main__.py" \
  --from-file=channels.py="${SOURCE_DIR}/notify/channels.py" \
  --from-file=checks.py="${SOURCE_DIR}/notify/checks.py" \
  --from-file=config.py="${SOURCE_DIR}/notify/config.py" \
  --from-file=engine.py="${SOURCE_DIR}/notify/engine.py" \
  --from-file=state.py="${SOURCE_DIR}/notify/state.py" \
  --from-file=types.py="${SOURCE_DIR}/notify/types.py" \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null

log "Applying Notify manifests"
kubectl apply -f "${MANIFEST_DIR}" >/dev/null

log "Restarting notify to load refreshed app code ConfigMap"
kubectl -n apps rollout restart deployment/notify >/dev/null
log "Waiting for notify rollout"
kubectl rollout status deployment/notify -n apps --timeout=300s

if kubectl -n apps get deployment/homepage >/dev/null 2>&1; then
  log "Restarting homepage to ensure dashboard config refresh"
  kubectl -n apps rollout restart deployment/homepage >/dev/null
  kubectl -n apps rollout status deployment/homepage --timeout=180s >/dev/null || \
    warn "homepage rollout status timed out"
fi

log "Notify deployed"
log "Check status: kubectl -n apps get pods -l app=notify"
log "Tail logs: kubectl -n apps logs deploy/notify --tail=100"
