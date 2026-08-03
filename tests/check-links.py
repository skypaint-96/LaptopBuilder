#!/usr/bin/env python3
"""Check relative Markdown links without making network requests."""
from __future__ import annotations

import re
import sys
from pathlib import Path
from urllib.parse import unquote

ROOT = Path(__file__).resolve().parents[1]
LINK = re.compile(r"(?<!!)\[[^\]]*\]\(([^)]+)\)")
failed = False
checked = 0

for markdown in sorted(ROOT.glob("**/*.md")):
    text = markdown.read_text(encoding="utf-8")
    for raw_target in LINK.findall(text):
        target = raw_target.strip().split(maxsplit=1)[0].strip("<>")
        if not target or target.startswith(("http://", "https://", "mailto:", "#")):
            continue
        target = unquote(target.split("#", 1)[0])
        resolved = (markdown.parent / target).resolve()
        checked += 1
        try:
            resolved.relative_to(ROOT)
        except ValueError:
            print(f"Link escapes repository: {markdown.relative_to(ROOT)} -> {target}", file=sys.stderr)
            failed = True
            continue
        if not resolved.exists():
            print(f"Broken relative link: {markdown.relative_to(ROOT)} -> {target}", file=sys.stderr)
            failed = True

if failed:
    raise SystemExit(1)
print(f"Checked {checked} relative Markdown link(s).")
