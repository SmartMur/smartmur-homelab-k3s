## Summary

- What changed:
- Why:

## Validation

- [ ] `bash -n scripts/*.sh`
- [ ] `pre-commit run --all-files`
- [ ] `python3 scripts/security_scrub.py --no-history`

## Security Checklist

- [ ] No secrets/tokens/private keys added
- [ ] Tracked app manifests contain no plaintext secret values
- [ ] Local-only artifacts (`terraform.tfvars`, kubeconfigs, node tokens) are not included

## Risks / Rollback

- Risk:
- Rollback plan:
