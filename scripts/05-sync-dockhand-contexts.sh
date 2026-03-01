#!/usr/bin/env bash
# Sync kubectl contexts into Dockhand environments.
# Note: this creates tracking entries in Dockhand; it does not add native Kubernetes APIs.
set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
log()  { echo -e "${GREEN}[✓]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
die()  { echo -e "${RED}[✗]${NC} $*"; exit 1; }

NAMESPACE="${DOCKHAND_NAMESPACE:-apps}"
DEPLOYMENT="${DOCKHAND_DEPLOYMENT:-dockhand}"
DB_PATH="${DOCKHAND_DB_PATH:-/app/data/db/dockhand.db}"
PREFIX="${DOCKHAND_ENV_PREFIX:-k8s-}"

sql_escape() {
  printf "%s" "$1" | sed "s/'/''/g"
}

sanitize_context() {
  printf "%s" "$1" | tr -c 'A-Za-z0-9._-' '-'
}

command -v kubectl >/dev/null 2>&1 || die "kubectl not found."
kubectl cluster-info >/dev/null 2>&1 || die "Cannot reach Kubernetes cluster."
kubectl -n "$NAMESPACE" get deploy "$DEPLOYMENT" >/dev/null 2>&1 || \
  die "Deployment $NAMESPACE/$DEPLOYMENT not found."

kubectl -n "$NAMESPACE" exec "deploy/$DEPLOYMENT" -- sh -lc "command -v sqlite3 >/dev/null 2>&1" || \
  die "sqlite3 is not available in the Dockhand container."

mapfile -t contexts < <(kubectl config get-contexts -o name 2>/dev/null || true)
if [[ "${#contexts[@]}" -eq 0 ]]; then
  current_ctx="$(kubectl config current-context 2>/dev/null || true)"
  [[ -n "$current_ctx" ]] && contexts=("$current_ctx")
fi
[[ "${#contexts[@]}" -gt 0 ]] || die "No kube contexts found in your kubeconfig."

created=0
updated=0

for raw_ctx in "${contexts[@]}"; do
  ctx="$(printf "%s" "$raw_ctx" | sed 's/^ *//;s/ *$//')"
  [[ -z "$ctx" ]] && continue

  safe_ctx="$(sanitize_context "$ctx")"
  env_name="${PREFIX}${safe_ctx}"
  env_sql="$(sql_escape "$env_name")"
  context_label_sql="$(sql_escape "context:$ctx")"

  existing_id="$(
    kubectl -n "$NAMESPACE" exec "deploy/$DEPLOYMENT" -- sh -lc \
      "sqlite3 '$DB_PATH' \"select id from environments where name='$env_sql' limit 1;\""
  )"

  if [[ -z "$existing_id" ]]; then
    kubectl -n "$NAMESPACE" exec "deploy/$DEPLOYMENT" -- sh -lc \
      "sqlite3 '$DB_PATH' \"insert into environments (name,host,port,protocol,icon,collect_activity,collect_metrics,highlight_changes,labels,connection_type,socket_path,created_at,updated_at) values ('$env_sql','edge-agent',2375,'http','globe',1,1,1,json_array('kubernetes','$context_label_sql'),'hawser-edge','/var/run/docker.sock',datetime('now'),datetime('now'));\""
    created=$((created + 1))
    log "Created Dockhand environment: $env_name (context: $ctx)"
  else
    kubectl -n "$NAMESPACE" exec "deploy/$DEPLOYMENT" -- sh -lc \
      "sqlite3 '$DB_PATH' \"update environments set host='edge-agent',port=2375,protocol='http',icon='globe',collect_activity=1,collect_metrics=1,highlight_changes=1,labels=json_array('kubernetes','$context_label_sql'),connection_type='hawser-edge',socket_path='/var/run/docker.sock',updated_at=datetime('now') where id=$existing_id;\""
    updated=$((updated + 1))
    log "Updated Dockhand environment: $env_name (context: $ctx)"
  fi
done

log "Sync complete. Created: $created | Updated: $updated"
echo ""
kubectl -n "$NAMESPACE" exec "deploy/$DEPLOYMENT" -- sh -lc \
  "sqlite3 '$DB_PATH' \"select id,name,connection_type,labels from environments where name like '$(sql_escape "${PREFIX}")%' order by id;\""
