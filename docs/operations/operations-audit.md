# Operations Audit - 2026-02-22

## Scope

Live environment audit and remediation executed on 2026-02-22 against:
- k3s cluster (`kubectl` from control node)
- k3s nodes via SSH (`K8-Master`, `k3s-worker-01`, `k3s-worker-02`, `k3s-worker-03`)
- TrueNAS relay host (`Truenas`)
- Docker edge host (`192.168.30.117`)

## Findings

1. Authentik instability from OOM kills
- `authentik` and `authentik-worker` had repeated restarts with `Last State: OOMKilled`.
- Worker kernel logs confirmed memory cgroup kills for Authentik worker processes.

2. Manifest drift versus live cluster PVCs
- `kubectl apply` failed for several apps because immutable PVC `storageClassName` in manifests did not match live PVCs.
- Affected PVCs:
  - `authentik-postgres-data`
  - `code-server-workspace`
  - `n8n-data`

3. Historical control-plane/runtime turbulence (resolved at audit time)
- Previous logs showed transient kubelet/API timeouts and lease renewal failures that explain historical restarts in `metrics-server` and `nfs-provisioner`.

4. Edge relay and proxy health
- TrueNAS relay config test passed (`nginx -t`).
- Docker host services were healthy.
- TrueNAS relay errors in logs were historical (mostly from 2026-02-21), with no new matching error lines during this audit window.

## Fixes Applied

1. Increased Authentik runtime resources
- Updated `manifests/apps/authentik/authentik.yml`:
  - `authentik`:
    - requests: `cpu: 500m`, `memory: 512Mi`
    - limits: `cpu: 1000m`, `memory: 1Gi`
  - `authentik-worker`:
    - requests: `cpu: 250m`, `memory: 384Mi`
    - limits: `cpu: 1000m`, `memory: 1Gi`
- Rolled out deployments and verified readiness with zero restarts on new pods.

2. Reconciled manifest storage classes to live immutable PVCs
- Updated manifests:
  - `manifests/apps/authentik/authentik.yml` -> `local-path`
  - `manifests/apps/code-server/code-server.yml` -> `local-path`
  - `manifests/apps/n8n/n8n.yml` -> `local-path`
- Result: server-side dry-run and apply are now consistent with live cluster state.

## Validation Snapshot (post-fix)

- `kubectl get nodes -o wide`: all nodes `Ready`
- `kubectl get pods -A`: all workloads in `Running` state at check time
- `kubectl top pods -A`: Authentik usage stabilized below new limits at audit time
- `kubectl get events -A --field-selector type=Warning`:
  - only residual warning from pre-fix Authentik worker pod restart history

## Recommended Follow-up

1. Plan a controlled storage migration for selected workloads from `local-path` to `truenas-nfs` if cross-node failover is required.
2. Add periodic restart/event trend checks (daily) to catch repeated transient failures earlier.
3. Keep a dated audit log in `docs/` for every production incident/remediation window.
