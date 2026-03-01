# Security Policy

## Supported Versions

Security fixes target the latest state of `main`.

## Rulebook

The operational rules and incident playbook live in:

- `docs/SECURITY_RULEBOOK.md`

All contributors are expected to follow that document for daily workflow and incident handling.

## Reporting Security Issues

Do not open public issues for sensitive vulnerabilities.

Use one of:
- GitHub Security Advisory (preferred)
- Maintainer private contact

Include:
- What is affected
- Reproduction details
- Impact severity

## Secret Leakage Response

If a secret is exposed:

1. Revoke or rotate immediately.
2. Remove secret from current branch.
3. Rewrite history if needed.
4. Re-run:
   - `pre-commit run --all-files`
   - `python3 scripts/security_scrub.py`
   - `bash -n scripts/*.sh`
5. Force-push only with explicit maintainer approval.

Use `docs/SECURITY_RULEBOOK.md` for command-level incident steps.

## Baseline Security Checks

- `pre-commit run --all-files`
- `python3 scripts/security_scrub.py`
- `bash -n scripts/*.sh`
- CI workflow: `.github/workflows/ci.yml`
