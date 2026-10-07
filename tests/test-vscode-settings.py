"""Non-destructive, repeatable VS Code settings merge tests (no VS Code required)."""

import importlib.util
import json
import sys
from pathlib import Path
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("merge_settings", ROOT / "scripts/merge-vscode-settings.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class SettingsMergeTests(unittest.TestCase):
    def test_jsonc_and_repeatable_merge(self):
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / "settings.json"
            target.write_text('''{
              // locally managed values
              "editor.formatOnSave": true,
              "local.url": "https://example.test/a//b",
              "local.list": [1, 2,], /* retained data */
              "terminal.integrated.profiles.linux": {"Local": {"path": "bash"}},
            }''', encoding="utf-8")
            module.merge(ROOT / "vscode/settings.json", target)
            merged = json.loads(target.read_text(encoding="utf-8"))
            self.assertEqual(merged["local.list"], [1, 2])
            self.assertEqual(merged["local.url"], "https://example.test/a//b")
            self.assertFalse(merged["editor.formatOnSave"])
            self.assertEqual(merged["terminal.integrated.profiles.linux"], {"PowerShell": {"path": "pwsh"}})
            first = target.read_bytes()
            module.merge(ROOT / "vscode/settings.json", target)
            self.assertEqual(target.read_bytes(), first)

    def test_missing_file_and_invalid_input(self):
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / "nested/settings.json"
            module.merge(ROOT / "vscode/settings.json", target)
            self.assertIn("editor.formatOnSave", json.loads(target.read_text(encoding="utf-8")))
            target.write_text("{ invalid", encoding="utf-8")
            with self.assertRaises(ValueError):
                module.merge(ROOT / "vscode/settings.json", target)
            self.assertEqual(target.read_text(encoding="utf-8"), "{ invalid")


if __name__ == "__main__":
    unittest.main()
