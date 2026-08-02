#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
if ! command -v ansible-playbook >/dev/null 2>&1; then
  echo 'Ansible syntax check skipped because ansible-playbook is not installed.' >&2
  exit 0
fi

ANSIBLE_CONFIG="$ROOT/ansible/ansible.cfg" \
  ansible-playbook \
    -i "$ROOT/ansible/inventory.ini" \
    "$ROOT/ansible/site.yml" \
    --syntax-check
