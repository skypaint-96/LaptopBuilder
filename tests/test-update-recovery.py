#!/usr/bin/env python3
"""Static safety checks; never run install, package, EFI, or disk commands."""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]


class RecoveryAndUpdateChecks(unittest.TestCase):
    def test_credentials_mounted_in_both_recovery_recipes(self):
        disk = (ROOT / "scripts/install/10-disk.sh").read_text()
        recovery = (ROOT / "docs/RECOVERY.md").read_text()
        target = "/mnt/var/lib/arch-workstation/pending-credentials"
        self.assertIn("@credentials", disk)
        self.assertIn("pending-credentials", disk)
        self.assertEqual(recovery.count(f"/dev/mapper/cryptroot {target}"), 2)
        self.assertEqual(recovery.count(f"subvol=@credentials /dev/mapper/cryptroot"), 2)

    def test_update_repairs_boot_before_aur_and_on_official_error(self):
        update = (ROOT / "scripts/update.sh").read_text()
        self.assertLess(update.index('sudo pacman "${pacman_args[@]}"'),
                        update.index('info "Stage 2/4:'))
        self.assertLess(update.index('info "Stage 2/4:'),
                        update.index('"$REPO_ROOT/scripts/install-aur.sh"'))
        self.assertIn('trap \'repair_boot_on_error "$?"\' ERR', update)
        self.assertLess(update.index("boot_stage_pending=true"),
                        update.index('sudo pacman "${pacman_args[@]}"'))
        self.assertIn('trap - ERR', update)
        self.assertIn('boot_stage_pending=false', update)

    def test_update_signs_prepared_keys_before_secure_boot_is_enabled(self):
        update = (ROOT / "scripts/update.sh").read_text()
        self.assertIn('elif sudo test -r /var/lib/sbctl/keys/db/db.key && sudo test -r /var/lib/sbctl/keys/db/db.pem; then', update)
        self.assertIn('load_runtime_security; rebuild_and_sign_ukis', update)
        self.assertIn('if ! refresh_boot_assets; then', update)
        self.assertIn('if bool_true "$sign_boot_assets"; then\n  refresh_boot_assets', update)
        self.assertLess(update.index('  refresh_boot_assets\nelse\n'), update.index('"$REPO_ROOT/scripts/install-aur.sh"'))

    def test_helper_is_built_before_atomic_conflict_transaction(self):
        aur = (ROOT / "scripts/install-aur.sh").read_text()
        self.assertNotIn('pacman_args=(-Rns)', aur)
        self.assertLess(aur.index('makepkg "${makepkg_args[@]}"'),
                        aur.index('sudo pacman "${pacman_args[@]}" "${artifacts[@]}"'))
        self.assertIn('makepkg --packagelist', aur)
        self.assertIn('pacman_args+=(--ask 4)', aur)
        self.assertNotRegex(aur, re.compile(r'pacman_args=\(-U\s+--needed'))


if __name__ == "__main__":
    unittest.main()
