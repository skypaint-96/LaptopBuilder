#!/usr/bin/env python3
from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SKIP_DIRS = {".git", "build", "dist", "usb/work", "usb/output"}
PATTERNS = [
    re.compile(r"BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY"),
    re.compile(r"AKIA[0-9A-Z]{16}"),
    re.compile(
        r'"(?:user_password|luks_passphrase|tpm2_pin|media_unlock_passphrase)"\s*:\s*"(?!example|placeholder|change-me)[^"$]{4,}"',
        re.IGNORECASE,
    ),
    re.compile(
        r"(?:PASSWORD|PASSPHRASE|TPM_PIN)\s*=\s*['\"](?!example|placeholder|change-me)[^'\"$]{4,}['\"]",
        re.IGNORECASE,
    ),
]

findings: list[str] = []
for path in ROOT.rglob("*"):
    if not path.is_file():
        continue
    relative = path.relative_to(ROOT)
    relative_text = str(relative)
    if any(relative_text == item or relative_text.startswith(f"{item}/") for item in SKIP_DIRS):
        continue
    if path.suffix.lower() in {".zip", ".gz", ".bundle", ".iso", ".png", ".jpg", ".gpg"}:
        continue
    try:
        text = path.read_text(encoding="utf-8")
    except (UnicodeDecodeError, OSError):
        continue
    for line_number, line in enumerate(text.splitlines(), start=1):
        if any(pattern.search(line) for pattern in PATTERNS):
            findings.append(f"{relative}:{line_number}: {line.strip()}")

if findings:
    print("Possible committed secret material detected:")
    print("\n".join(findings))
    raise SystemExit(1)

print("No likely committed credentials detected.")
