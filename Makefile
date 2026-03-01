.PHONY: lint security hooks precommit check

lint:
	bash -n scripts/*.sh

security:
	python3 scripts/security_scrub.py --no-history

hooks:
	pre-commit install

precommit:
	pre-commit run --all-files

check: lint security precommit
