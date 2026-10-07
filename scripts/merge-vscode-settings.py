#!/usr/bin/env python3
"""Merge repo-managed top-level VS Code keys into a user's JSONC settings."""

import json
import os
from pathlib import Path
import sys
import tempfile


def parse_jsonc(text):
    # Mask comments without changing quoted strings; JSONC also permits trailing commas.
    result = []
    index = 0
    quoted = False
    while index < len(text):
        char = text[index]
        if quoted:
            result.append(char)
            if char == "\\" and index + 1 < len(text):
                index += 1
                result.append(text[index])
            elif char == '"':
                quoted = False
        elif char == '"':
            quoted = True
            result.append(char)
        elif text.startswith("//", index):
            end = text.find("\n", index)
            if end == -1:
                end = len(text)
            result.extend(" " * (end - index))
            index = end - 1
        elif text.startswith("/*", index):
            end = text.find("*/", index + 2)
            if end == -1:
                raise ValueError("Unterminated JSONC comment")
            result.extend("\n" if c == "\n" else " " for c in text[index : end + 2])
            index = end + 1
        else:
            result.append(char)
        index += 1
    stripped = "".join(result)
    # Match commas outside strings only (including strings containing comment markers).
    result = []
    index = 0
    quoted = False
    while index < len(stripped):
        char = stripped[index]
        if quoted:
            result.append(char)
            if char == "\\" and index + 1 < len(stripped):
                index += 1
                result.append(stripped[index])
            elif char == '"':
                quoted = False
        else:
            if char == '"':
                quoted = True
            if char == "," and stripped[index + 1 :].lstrip().startswith(("}", "]")):
                char = " "
            result.append(char)
        index += 1
    data = json.loads("".join(result))
    if not isinstance(data, dict):
        raise ValueError("VS Code settings must be an object")
    return data


def merge(managed_path, settings_path):
    managed = parse_jsonc(managed_path.read_text(encoding="utf-8"))
    existing = parse_jsonc(settings_path.read_text(encoding="utf-8")) if settings_path.exists() else {}
    merged = {**existing, **managed}
    if merged == existing:
        return
    output = json.dumps(merged, ensure_ascii=False, indent=2) + "\n"
    settings_path.parent.mkdir(parents=True, exist_ok=True)
    fd, temp_path = tempfile.mkstemp(prefix=".settings.", dir=settings_path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            stream.write(output)
        os.chmod(temp_path, settings_path.stat().st_mode & 0o777 if settings_path.exists() else 0o644)
        os.replace(temp_path, settings_path)
    finally:
        if os.path.exists(temp_path):
            os.unlink(temp_path)


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit("Usage: merge-vscode-settings.py MANAGED_JSON USER_JSON")
    try:
        merge(Path(sys.argv[1]), Path(sys.argv[2]))
    except (OSError, ValueError) as exc:
        sys.exit(f"Cannot merge VS Code settings: {exc}")
