# Security Rulebook

Last updated: 2026-02-22

This rulebook defines mandatory security workflow for this repository.

## 1. Core Principles

1. Stop the line on security risks.
2. Secrets never belong in tracked files.
3. Tracked app manifests must reference secrets by name, not value.
4. Run security checks before pushing.
5. Treat any leak as a formal incident.

## 2. Non-Negotiable Rules

1. Never commit:
   - tokens, API keys, kubeconfigs, or private keys
   - machine-specific credentials and runtime secrets
   - local files like `.k3s-node-token`, `kubeconfig-raw.yml`, `terraform/terraform.tfvars`
2. Keep tracked app manifests secret-free (no plaintext `stringData` values).
3. Use placeholders in docs and examples:
   - `CHANGE_ME_*`
   - `${ENV_VAR}`
4. Required local checks before push:
   - `pre-commit run --all-files`
   - `bash -n scripts/*.sh`
   - `python3 scripts/security_scrub.py --no-history`

## 3. Standard Workflow

### Before coding

- Pull latest `main`.
- Confirm no secret-bearing local files are staged.
- Use placeholders for new secret fields in manifests/docs.

### During coding

- Keep credentials in local password manager or local-only files.
- Do not place real values in `stringData` in tracked manifests.

### Before commit

```bash
git status
pre-commit run --all-files
bash -n scripts/*.sh
python3 scripts/security_scrub.py --no-history
```

### Before push

```bash
pre-commit run --all-files
bash -n scripts/*.sh
python3 scripts/security_scrub.py
```

### After push

- Confirm CI `.github/workflows/ci.yml` passed.
- If any leak is found, start incident handling immediately.

## 4. Security Incident Playbook

### Trigger conditions

- Secret/token/key appears in tracked content.
- `security_scrub.py` reports high-severity findings.
- Sensitive local file is committed by mistake.

### Immediate response

1. Freeze pushes and merges on affected branch.
2. Revoke or rotate exposed credentials immediately.
3. Remove leaked content from current branch.
4. Re-run local checks.

### If history is affected

1. Create safety tag:

```bash
git tag pre-history-scrub-$(date +%Y%m%d-%H%M%S)
```

2. Rewrite with `git-filter-repo` using:
   - `--replace-text` for leaked literals
   - `--invert-paths` for files that should never be tracked
3. Verify removal:

```bash
git log --all -S"<leaked-value>" --oneline
git rev-list --all -- <sensitive/path>
```

4. Force-push rewritten refs:

```bash
git push --force origin main
```

5. Notify collaborators to re-clone or hard reset.

### Collaborator recovery

```bash
git fetch origin
git checkout main
git reset --hard origin/main
```

## 5. Documentation Rules

1. Keep `SECURITY.md` and this rulebook aligned.
2. Never include realistic secrets in docs or examples.
3. Replace exposed values with `REDACTED_*` markers.
4. Update docs in the same PR as security-sensitive changes.

## 6. Reference Commands

```bash
# Quick local gate
pre-commit run --all-files
bash -n scripts/*.sh
python3 scripts/security_scrub.py --no-history

# Full scrub including git history
python3 scripts/security_scrub.py
```
