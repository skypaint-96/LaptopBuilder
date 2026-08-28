# Application authentication and OneDrive

The repository manages packages, services, and non-secret settings. It does not
copy active OAuth tokens, browser cookies, GitHub tokens, Microsoft sessions, or
password-manager state into Git or the installation USB.

## First-login wizard

When `ENABLE_FIRST_LOGIN_AUTH=true`, Ansible installs an Xfce autostart entry.
It remains dormant until `/var/lib/arch-workstation/complete` exists, then opens
one terminal wizard on the next graphical login:

```bash
archctl auth --first-login
```

The wizard supports:

- Microsoft Edge first-run preparation before any browser OAuth link is opened;
- GitHub CLI browser authentication and Git credential-helper setup;
- OneDrive browser OAuth followed by a real initial sync, safe folder linking, and user service enablement;
- opening Visual Studio Code for Settings Sync sign-in;
- opening Microsoft Edge for profile sync sign-in;
- opening Steam for account sign-in.

GUI-only applications cannot expose a reliable command-line test for their full
account state. The wizard therefore asks you to confirm completion and records a
local marker under `~/.local/state/arch-workstation/auth/`. Those markers contain
no credentials. Reset them with:

```bash
archctl auth reset
```

Run or inspect authentication at any time:

```bash
archctl auth
archctl auth github
archctl auth onedrive
archctl auth onedrive-status
archctl auth onedrive-logs
archctl auth status
```

## OneDrive configuration

The maintained Linux client is installed from the AUR package
`onedrive-abraunegg`. The managed configuration is written to:

```text
~/.config/onedrive/config
```

The default sync directory is:

```text
~/OneDrive
```

The client performs interactive browser OAuth when run in a graphical session.
Its refresh token remains in the user's private OneDrive configuration directory
and is not copied into the project, USB cache, snapshots of the project, or build
artifacts.

The normal continuous-monitor service is not enabled until authentication and the
initial transaction succeed. After OAuth, `archctl auth onedrive` queues the
one-shot user service and returns control to the terminal:

```bash
systemctl --user start --no-block arch-workstation-onedrive-bootstrap.service
```

That service performs the dry run, initial synchronisation, safe folder migration,
a second upload sync, and finally enables the normal monitor service:

```bash
systemctl --user enable --now onedrive.service
```

Monitor it without keeping the authentication terminal occupied:

```bash
archctl auth onedrive-status
archctl auth onedrive-logs
```

A best-effort desktop notification reports completion or failure. The journal is
the authoritative log.

## Safe home-folder linking

After the initial sync, the default policy links:

```text
~/Documents -> ~/OneDrive/Documents
~/Pictures  -> ~/OneDrive/Pictures
~/Videos    -> ~/OneDrive/Videos
```

For each existing local directory, the wizard:

1. creates the matching OneDrive directory;
2. copies only files whose names do not already exist remotely;
3. retains the complete original local directory in a dated backup under
   `~/.local/share/arch-workstation/folder-backups/`;
4. creates the symbolic link;
5. performs another OneDrive sync to upload the newly copied files.

Existing remote files are never overwritten by this migration. Name collisions
remain available in the dated local backup for manual comparison. Existing
symbolic links, mount points, and non-directory paths are left unchanged.

OneDrive is a synchronisation service, not a complete backup system. Keep a
separate backup for important data.

## Configuration values

```bash
ENABLE_ONEDRIVE=true
ONEDRIVE_PROFILES=""
ONEDRIVE_SYNC_DIR="OneDrive"
ONEDRIVE_LINK_DIRS="Documents Pictures Videos"
ONEDRIVE_SKIP_DOTFILES=true
ONEDRIVE_SKIP_SYMLINKS=true
ONEDRIVE_USE_RECYCLE_BIN=true
ONEDRIVE_ENABLE_SERVICE=true
ONEDRIVE_INITIAL_SYNC_BACKGROUND=true
ONEDRIVE_NOTIFY_ON_COMPLETION=true

ENABLE_FIRST_LOGIN_AUTH=true
AUTH_GITHUB_CLI=true
GITHUB_GIT_PROTOCOL="https"
AUTH_ONEDRIVE=true
AUTH_VSCODE=true
AUTH_EDGE=true
AUTH_STEAM=true
EDGE_PREPARE_BEFORE_OAUTH=true
```

`ONEDRIVE_SYNC_DIR` is deliberately restricted to a path relative to the user's
home directory. `ONEDRIVE_LINK_DIRS` accepts simple top-level directory names.
Set `ONEDRIVE_PROFILES` to add multiple accounts using `name:sync-dir:link1,link2`
entries, for example `personal:OneDrive:Documents,Pictures work:OneDrive-Work:`.
When `ONEDRIVE_PROFILES` is empty, the legacy single-profile variables remain in use.

## Upstream documentation

- OneDrive client usage and authentication: https://github.com/abraunegg/onedrive/blob/master/docs/usage.md
- OneDrive configuration options: https://github.com/abraunegg/onedrive/blob/master/docs/application-config-options.md
- GitHub CLI authentication: https://cli.github.com/manual/gh_auth_login
- GitHub CLI Git credential setup: https://cli.github.com/manual/gh_auth_setup-git
- Visual Studio Code Settings Sync: https://code.visualstudio.com/docs/configure/settings-sync
