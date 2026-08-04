SHELL := /usr/bin/env bash

.PHONY: test lint config structure ansible powershell

test: lint config structure ansible powershell

lint:
	./tests/lint.sh

config:
	./tests/test-config.sh

structure:
	./tests/check-repo.sh
	./tests/test-source-copy.sh
	./tests/test-upgrade-existing.sh
	./tests/test-package-lists.sh
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
