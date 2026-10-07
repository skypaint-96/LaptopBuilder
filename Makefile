SHELL := /usr/bin/env bash

.PHONY: test test-strict require-validators lint config structure ansible powershell

# Local development: optional ShellCheck, Ansible and PowerShell checks report skips.
test: lint config structure ansible powershell

# Release/CI: fail before running tests if any optional validator is unavailable.
test-strict:
	@$(MAKE) require-validators
	@$(MAKE) test

require-validators:
	@for tool in bash python3 shellcheck ansible-playbook pwsh; do \
		command -v "$$tool" >/dev/null 2>&1 || { echo "Required validator missing: $$tool" >&2; exit 1; }; \
	done
	@python3 -c 'import yaml' || { echo 'Required validator missing: PyYAML (see tests/requirements.txt)' >&2; exit 1; }

lint:
	./tests/lint.sh

config:
	./tests/test-config.sh

structure:
	./tests/check-repo.sh
	./tests/test-source-copy.sh
	./tests/test-upgrade-existing.sh
	./tests/test-package-lists.sh
	python3 ./tests/test-vscode-settings.py
	python3 ./tests/test-update-recovery.py
	./tests/test-security-state.sh
	./tests/test-usb-layout.sh
	./tests/test-usb-secrets.sh
	./tests/test-usb-cache.sh
	./tests/test-staged-credentials.sh
	./tests/test-auth.sh

ansible:
	./tests/ansible-syntax.sh

powershell:
	@if command -v pwsh >/dev/null 2>&1; then \
		pwsh -NoLogo -NoProfile -File ./tests/Test-PowerShell.ps1; \
	else \
		echo 'PowerShell parser check skipped because pwsh is not installed.' >&2; \
	fi
