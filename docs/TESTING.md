# Testing and validation

The repository separates static validation from destructive integration testing.

## Local static checks

Run from the repository root:

```bash
make test
```

This checks:

- Bash syntax and, when installed, ShellCheck findings;
- configuration defaults and invalid dependency combinations;
- YAML and JSON syntax;
- relative documentation links;
- repository structure and safety assertions;
- TPM token/crypttab completion-state behaviour;
- Ansible playbook syntax when `ansible-playbook` is available;
- PowerShell parser errors when `pwsh` is available.

The checks do not partition a disk, enroll firmware keys, or alter a TPM.

## Continuous integration

The GitHub Actions workflow runs the static suite with ShellCheck, Ansible Core, and PowerShell available. A separate disposable Arch container resolves every official package name from the current repositories and checks the configured AUR names through the AUR metadata API.

Package resolution proves that names and repository dependencies currently resolve; it does not prove that an AUR PKGBUILD is trustworthy or that an application works on the target hardware.

## Destructive integration test matrix

Before using an important disk, test a release in a disposable x86-64 UEFI virtual machine with:

1. an empty virtual disk;
2. UEFI variable persistence;
3. Secure Boot Setup Mode and owner-key enrollment;
4. a virtual TPM 2.0;
5. one full install, provision, Secure Boot, TPM enrollment, update, and recovery cycle.

Then test on a spare T480 SSD. Confirm Wi-Fi, audio, suspend/resume, both kernels, Docker, Steam, external displays, USB-C/Thunderbolt, TPM/PIN unlock, and passphrase fallback. Firmware behaviour cannot be fully validated by static checks or a virtual machine.

## Version 0.2 regression coverage

The structural suite asserts package-source resolution before disk erasure, `paru-bin` bootstrap, single-session sudo/Ansible invocation, automatic target Secure Boot preparation, discovery/signing of every EFI binary, resumable first-boot state detection, and signed update repair. A real UEFI integration test is still required to validate firmware key enrolment and TPM behaviour on each hardware model.
