# Testing and validation

The repository separates non-destructive static checks from destructive integration testing.

## Local suite

Run:

```bash
make test
```

It performs:

- `bash -n` over installer, USB, security and test scripts;
- ShellCheck when installed;
- YAML and JSON parsing;
- relative documentation-link validation;
- configuration default and invalid-combination tests;
- repository structure and destructive-safety assertions;
- installed source-snapshot exclusion/provenance checks;
- synthetic USB A/B layout, repository checksum and fallback tests;
- simulated interrupted Arch-slot and package-cache activation recovery;
- Ansible syntax when available;
- PowerShell parser checks when available.

The synthetic USB test creates ordinary temporary directories and dummy slot files. It does not partition a disk, boot firmware or download an ISO.

## Continuous integration

GitHub Actions installs ShellCheck, Ansible Core and uses the available PowerShell parser. A disposable current Arch container obtains the package list from `scripts/lib/packages.sh`, enables multilib and asks pacman to resolve Intel, AMD and generic profile combinations. It also checks configured AUR names through the AUR metadata API.

Resolution proves current names/dependencies exist. It does not establish AUR trust, USB bootability or hardware compatibility.

## USB integration matrix

Use a disposable USB and test:

1. basic USB creation from a supported Linux host;
2. UEFI removable boot;
3. active and recovery GRUB entries;
4. automated `start.sh` launch;
5. Wi-Fi setup and public GitHub refresh;
6. repository current-to-previous rotation;
7. deliberate current checksum damage and previous fallback;
8. Arch refresh into the non-running slot;
9. reboot into the new slot and recovery boot into the old slot;
10. interrupted download/write scenarios;
11. boot and install with the USB deliberately mounted read-only;
12. full package-cache refresh with AUR review and staged dependency resolution;
13. forced offline preflight and installation in a network-isolated environment;
14. confirm `/opt/arch-workstation/BUILD_COMMIT` matches the accepted USB/GitHub generation.

Do not simulate update failure by unplugging a USB while its FAT filesystem is actively writing unless the device is disposable; use controlled process termination first.

## Target integration matrix

Before using an important SSD, test in a disposable x86-64 UEFI VM with variable persistence and virtual TPM 2.0:

1. full install from online-first mode;
2. full install from forced offline cache;
3. first-boot provisioning without a network after offline installation;
4. owner-key Secure Boot enrollment;
5. signed normal and LTS UKIs;
6. TPM/PIN and passphrase fallback;
7. `archctl update` and re-signing;
8. chroot recovery and snapshot rollback.

Then use a spare T480 SSD and test Wi-Fi, audio, Bluetooth, suspend/resume, external displays, USB-C/Thunderbolt, Docker, Steam, both kernels, firmware updates and both unlock paths.

Static checks cannot validate your firmware's key-enrollment interface, TPM behaviour, exact T480 hardware variant or physical USB controller reliability.
