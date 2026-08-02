# Contributing

Changes should preserve the repository's narrow safety boundaries and reproducibility goals.

1. Do not weaken whole-disk confirmation, secret handling, Secure Boot enrollment confirmation, or passphrase recovery.
2. Prefer official Arch packages. Keep AUR additions explicit and reviewable.
3. Make provisioning changes safe to run repeatedly.
4. Update documentation and verification checks with behavioural changes.
5. Add official package-name changes to `tests/check-arch-packages.sh`, and fixed AUR-name changes to `tests/check-aur-packages.sh`.
6. Run `make test` before committing.
7. Never commit `config/install.conf`, secret files, private keys, recovery keys, or sbctl key material.

Destructive installer changes should be tested in a disposable UEFI virtual machine and on spare hardware before use on important systems. Virtual TPM and Secure Boot testing does not replace validation on the target firmware.
