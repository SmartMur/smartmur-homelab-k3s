# Contributing

Thanks for improving this cluster automation repo.

## Local Setup

```bash
git clone <your-fork-or-origin-url> k3s-cluster
cd k3s-cluster
```

Install local hooks once:

```bash
brew install pre-commit
pre-commit install
```

## Required Checks Before PR

```bash
bash -n scripts/*.sh
pre-commit run --all-files
python3 scripts/security_scrub.py --no-history
```

For security-sensitive changes, also review `docs/SECURITY_RULEBOOK.md`.

## Contribution Rules

- Keep changes focused and reversible.
- Never commit secrets, kubeconfigs, tokens, or machine-specific credentials.
- Keep tracked manifests secret-free; real values must live in local-only secret overlays.
- Document workflow changes in `README.md` and `STACK.md`.
- Follow `docs/SECURITY_RULEBOOK.md` incident flow if leakage is detected.

## PR Checklist

- What changed and why
- How it was tested
- Risk notes (if any)
