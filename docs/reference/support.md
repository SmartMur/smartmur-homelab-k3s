# Support

## Getting Help

1. Review `docs/GETTING_STARTED.md` for baseline setup flow.
2. Review `STACK.md` for environment architecture and operations.
3. Run local validation:

```bash
bash -n scripts/*.sh
python3 scripts/security_scrub.py --no-history
```

## Issue Reports

When opening an issue, include:
- What command failed
- Full error output
- What you expected
- What changed since last known-good run

For security issues, follow `SECURITY.md` and avoid public disclosure.
