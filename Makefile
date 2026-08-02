SHELL := /usr/bin/env bash

.PHONY: test lint config structure usb ansible powershell

test: lint config structure usb ansible powershell

lint:
	./tests/lint.sh

config:
	./tests/test-config.sh

structure:
	./tests/check-repo.sh
	./tests/test-source-copy.sh

usb:
	./tests/test-usb.sh

ansible:
	./tests/ansible-syntax.sh

powershell:
	@if command -v pwsh >/dev/null 2>&1; then \
		pwsh -NoLogo -NoProfile -File ./tests/Test-PowerShell.ps1; \
	else \
		echo 'PowerShell parser check skipped because pwsh is not installed.' >&2; \
	fi
