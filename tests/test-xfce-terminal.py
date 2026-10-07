#!/usr/bin/env python3
"""Exercise the real xfconf command writer without installing Xfce."""

import os
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

import yaml


ROOT = Path(__file__).resolve().parents[1]
TASKS = yaml.safe_load((ROOT / "ansible/roles/desktop/tasks/main.yml").read_text())
SCRIPT = ROOT / "scripts/configure-xfce-terminal.sh"


class TerminalConfigTests(unittest.TestCase):
    def test_task_targets_user_channel_instead_of_legacy_file(self):
        task = next(t for t in TASKS if t["name"].startswith("Configure Xfce Terminal"))
        self.assertEqual(task["become_user"], "{{ arch_user }}")
        self.assertEqual(task["environment"]["XDG_RUNTIME_DIR"],
                         "/run/user/{{ getent_passwd[arch_user][1] }}")
        self.assertEqual(task["ansible.builtin.command"]["argv"][-1], "{{ xfce_terminal_custom_command }}")
        self.assertIn("scripts/configure-xfce-terminal.sh", task["ansible.builtin.command"]["argv"][1])
        self.assertNotIn("terminalrc", (ROOT / "ansible/roles/desktop/tasks/main.yml").read_text())

    @unittest.skipIf(os.name == "nt", "xfconf stub requires POSIX executable scripts")
    def test_custom_command_and_disabled_default_are_idempotent(self):
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            (directory / "xfconf-query").write_text(
                "#!/usr/bin/env python3\n"
                "import json, os, sys\n"
                "from pathlib import Path\n"
                "p = Path(os.environ['MOCK_XFCONF'])\n"
                "values = json.loads(p.read_text()) if p.exists() else {}\n"
                "args = sys.argv[1:]\n"
                "assert args[args.index('--channel') + 1] == 'xfce4-terminal'\n"
                "key = args[args.index('--property') + 1]\n"
                "if '--type' not in args:\n"
                "    if key not in values: sys.exit(1)\n"
                "    print(values[key]); sys.exit(0)\n"
                "values[key] = next(arg.split('=', 1)[1] for arg in args if arg.startswith('--set='))\n"
                "p.write_text(json.dumps(values))\n",
                encoding="utf-8",
            )
            (directory / "xfconf-query").chmod(0o755)
            env = dict(os.environ, PATH=f"{directory}{os.pathsep}{os.environ['PATH']}",
                       MOCK_XFCONF=str(directory / "channel.json"), XFCE_TERMINAL_IN_BUS="1")

            def apply(command):
                return subprocess.run(["bash", str(SCRIPT), command], env=env, text=True,
                                      capture_output=True, check=True).stdout.strip()

            command = 'env TITLE="work desk" sh -c \'echo $HOME; echo {{ 1 + 1 }}; echo x=y\''
            self.assertEqual(apply(command), "XFCE_TERMINAL_CHANGED")
            self.assertEqual(apply(command), "")
            self.assertEqual(json.loads((directory / "channel.json").read_text()),
                             {"/custom-command": command, "/run-custom-command": "true"})
            self.assertEqual(apply(""), "XFCE_TERMINAL_CHANGED")
            self.assertEqual(apply(""), "")
            self.assertEqual(json.loads((directory / "channel.json").read_text()),
                             {"/custom-command": "", "/run-custom-command": "false"})


if __name__ == "__main__":
    unittest.main()
