#!/usr/bin/env python3
"""Parse repository YAML files with PyYAML."""
from __future__ import annotations

import sys
from pathlib import Path

try:
    import yaml
except ImportError as exc:
    print("PyYAML is required: python -m pip install -r tests/requirements.txt", file=sys.stderr)
    raise SystemExit(2) from exc

ROOT = Path(__file__).resolve().parents[1]
files = sorted(ROOT.glob("**/*.yml")) + sorted(ROOT.glob("**/*.yaml"))
if not files:
    print("No YAML files found", file=sys.stderr)
    raise SystemExit(1)

failed = False
for path in files:
    try:
        with path.open("r", encoding="utf-8") as handle:
            list(yaml.safe_load_all(handle))
    except Exception as exc:  # PyYAML exposes several parser exception classes.
        failed = True
        print(f"YAML error in {path.relative_to(ROOT)}: {exc}", file=sys.stderr)

if failed:
    raise SystemExit(1)
print(f"Parsed {len(files)} YAML file(s).")
