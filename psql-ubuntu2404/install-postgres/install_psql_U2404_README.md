# PostgreSQL Installation — Ubuntu 24.04 (Noble Numbat)

> **Companion scripts** for installing, configuring, and uninstalling PostgreSQL
> using the **movedir** pattern on Ubuntu 24.04.
> Also compatible with Ubuntu 22.04 (see [Compatibility](#compatibility)).

---

## Table of Contents

- [Overview](#overview)
- [The Movedir Pattern](#the-movedir-pattern)
- [Directory Layout](#directory-layout)
- [Files in This Directory](#files-in-this-directory)
- [Quick Start](#quick-start)
- [Version Configuration](#version-configuration)
- [Installation Script](#installation-script)
- [Uninstallation Script](#uninstallation-script)
- [Companion Scripts](#companion-scripts)
- [What Gets Created on Disk](#what-gets-created-on-disk)
- [Compatibility](#compatibility)
- [Troubleshooting](#troubleshooting)

---

## Overview

This collection of scripts provides a repeatable, structured way to install
PostgreSQL on Ubuntu 24.04 inside a Docker container. The installation follows
the **movedir** pattern: the default PostgreSQL data directory is relocated to a
custom path (typically on a dedicated volume), and a symlink is placed in the
original location so PostgreSQL continues to find its data without any
configuration change.

All scripts share a single version source of truth (`pg-config.env`) and use
dynamic path resolution so they work correctly regardless of where they are
mounted inside the container.

---

## The Movedir Pattern

PostgreSQL's default data directory is:

```
/var/lib/postgresql/<VERSION>/main
```

This works for simple setups, but in Docker or multi-disk environments you
often want the data on a separate volume for performance, backup isolation, or
capacity reasons. The movedir pattern solves this without changing
`postgresql.conf`:

```
Before install:
  /var/lib/postgresql/13/main/   ← real directory (default)

After install:
  /db/mypg13/                    ← real data (on a dedicated volume)
  /var/lib/postgresql/13/main    ← symlink → /db/mypg13
  /var/lib/postgresql/13/main_ORIG/  ← backup of original (preserved)
```

PostgreSQL sees the same path it always expects. The actual data lives on the
volume you control.

---

## Directory Layout

```
install-postgres/
│
├── pg-config.env                        ← Shared version config (edit here)
│
├── install_psql_U2404_v1-movedir.sh     ← Main install script
├── uninstall_psql_U2404_v1-movedir.sh   ← Main uninstall script
│
├── psql_postgres_sudo.sh                ← Configures sudo for postgres user
├── psql_postgres_environment.sh         ← Sets up .bashrc, aliases, PS1
├── copy_psql_management_files.sh        ← Copies config + management scripts
│
└── install_psql_U2404_README.md         ← This file
```

---

## Files in This Directory

### `pg-config.env` — Version Configuration
Single source of truth for `PG_VERSION`. Sourced automatically by the install
and uninstall scripts at startup.

```bash
# Edit only this file to change the default version for all scripts
PG_VERSION=13
```

---

### `install_psql_U2404_v1-movedir.sh` — Main Install Script

Installs and fully configures PostgreSQL. Run as root.

**What it does (in order):**

| Step | Action |
|------|--------|
| 1 | Validates OS (Ubuntu), warns if not 24.04 |
| 2 | Skips if `psql` is already installed |
| 3 | Adds PGDG apt repository with GPG key (`chmod 644` for `_apt` user) |
| 4 | Installs `postgresql-<VERSION>`, `postgresql-contrib-<VERSION>`, `python3-psycopg2` |
| 5 | Moves data directory to `/db/mypg<VERSION>`, creates symlink |
| 6 | Creates log directory `/var/log/postgres` |
| 7 | Creates lock directory `/var/run/postgresql` |
| 8 | *(Optional)* Copies config + management files via `copy_psql_management_files.sh` |
| 9 | *(Optional)* Configures sudo access for `postgres` user |
| 10 | *(Optional)* Sets up shell environment for `postgres` user (`.bashrc`, aliases) |
| 11 | Enables and starts the `postgresql` systemd service |
| 12 | Verifies installation (directories, binary, service, connectivity) |

**Optional steps** (steps 8–10) run with `|| true` — they warn on failure but
do not abort the installation.

---

### `uninstall_psql_U2404_v1-movedir.sh` — Main Uninstall Script

Reverses everything the install script did. Run as root.

**What it does (in reverse install order):**

| Step | Action |
|------|--------|
| 1 | Prompts for confirmation (must type `yes`) |
| 2 | Stops and disables the `postgresql` systemd service |
| 3 | Removes symlink at `/var/lib/postgresql/<VERSION>/main` |
| 4 | Restores `_ORIG` backup if it exists |
| 5 | Optionally deletes `/db/mypg<VERSION>` (requires `--purge-data` flag) |
| 6 | Removes `/var/log/postgres` |
| 7 | Removes `/var/run/postgresql` |
| 8 | Purges packages: `apt-get purge` + autoremove |
| 9 | Removes PGDG apt source list and GPG keyring |
| 10 | Verifies system is clean |

> ⚠️ **Data safety**: The custom data directory `/db/mypg<VERSION>` is
> **preserved by default**. Pass `--purge-data` to delete it permanently.

---

### `psql_postgres_sudo.sh` — Sudo Configuration

Called by the install script (optional step). Configures passwordless sudo
access for the `postgres` OS user.

**What it does:**
- Adds `postgres` to the `sudo` group (or `wheel` on RHEL-based systems)
- Writes `/etc/sudoers.d/postgres` with `NOPASSWD:ALL`
- Verifies sudo access works by testing a privileged command

---

### `psql_postgres_environment.sh` — Shell Environment Setup

Called by the install script (optional step) with two arguments:

```bash
bash psql_postgres_environment.sh /var/lib/postgresql <PG_VERSION>
```

**What it does:**

| File created | Purpose |
|---|---|
| `$PGHOME/.bashrc` | Custom PS1 prompt (colored, shows date/time/user/path) |
| `$PGHOME/.bash_profile` | Sources `.bashrc` on login |
| `$PGHOME/.aliasrc` | `pgstart`, `pgstop`, `pgstatus` aliases |

The aliases target the correct systemd service unit for the installed version:

```bash
alias pgstart='sudo systemctl start postgresql@13-main.service --no-pager'
alias pgstop='sudo systemctl stop postgresql@13-main.service --no-pager'
alias pgstatus='sudo systemctl status postgresql@13-main.service --no-pager'
```

> **Note:** `PG_VERSION` is passed explicitly from the install script so the
> aliases always match the installed version — they are not hardcoded.

---

### `copy_psql_management_files.sh` — Management Files

Called by the install script (optional step). Copies PostgreSQL configuration
and management scripts into place.

**What it does:**

| Action | Detail |
|--------|--------|
| Copies `postgresql.conf` | → `/etc/postgresql/<VERSION>/main/postgresql.conf` |
| Copies `pg_hba.conf` | → `/etc/postgresql/<VERSION>/main/pg_hba.conf` |
| Creates `/var/lib/pgsql/bin/` | Management script bin directory |
| Copies management scripts | `pstart.sh`, `pstop.sh`, `pstatus.sh`, `psreload.sh` |
| Creates symlinks | Each script linked from `/usr/local/bin/<name>` (without `.sh`) |

Source config files are read from:
```
<script_dir>/../postgres-config-files/
```

The process mgmt files are soft links.
```
-> ls -l /usr/local/bin
total 0
lrwxrwxrwx 1 root root 30 Apr  5 00:58 psreload -> /var/lib/pgsql/bin/psreload.sh*
lrwxrwxrwx 1 root root 28 Apr  5 00:58 pstart -> /var/lib/pgsql/bin/pstart.sh*
lrwxrwxrwx 1 root root 29 Apr  5 00:58 pstatus -> /var/lib/pgsql/bin/pstatus.sh*
lrwxrwxrwx 1 root root 27 Apr  5 00:58 pstop -> /var/lib/pgsql/bin/pstop.sh*
```

---

## Quick Start

### Install (default version from `pg-config.env`)
```bash
sudo ./install_psql_U2404_v1-movedir.sh
```

### Install a specific version
```bash
sudo ./install_psql_U2404_v1-movedir.sh 16
```

### Show help
```bash
./install_psql_U2404_v1-movedir.sh --help
```

### Uninstall (preserve data directory)
```bash
sudo ./uninstall_psql_U2404_v1-movedir.sh
```

### Uninstall and delete all data
```bash
sudo ./uninstall_psql_U2404_v1-movedir.sh --purge-data
```

### Uninstall a specific version
```bash
sudo ./uninstall_psql_U2404_v1-movedir.sh 16 --purge-data
```

---

## Version Configuration

The PostgreSQL version is resolved using this priority chain (highest → lowest):

| Priority | Source | Example |
|----------|--------|---------|
| 1 | CLI argument | `./install_psql_U2404_v1-movedir.sh 17` |
| 2 | Shell environment variable | `export PG_VERSION=17` |
| 3 | `pg-config.env` | `PG_VERSION=13` ← **edit here for team default** |
| 4 | Built-in fallback | `16` |

**To change the default version for all scripts**, edit only `pg-config.env`:

```bash
# pg-config.env
PG_VERSION=16   # ← change this one line
```

Both the install and uninstall scripts source this file automatically at
startup using `BASH_SOURCE[0]` — they find the file relative to their own
location, so it works regardless of where you `cd` from.

---

## What Gets Created on Disk

After a successful installation (example: PG version 13):

```
/db/mypg13/                               ← actual data directory (volume)
  PG_VERSION
  base/
  global/
  pg_hba.conf
  postgresql.conf
  ...

/var/lib/postgresql/
  13/
    main -> /db/mypg13                    ← symlink (movedir)
    main_ORIG/                            ← preserved original (backup)

/var/log/postgres/                        ← log directory (postgres:postgres 700)
/var/run/postgresql/                      ← lock/socket directory (postgres:postgres 755)

/etc/apt/sources.list.d/pgdg.list         ← PGDG apt repository
/usr/share/keyrings/postgresql-keyring.gpg ← PGDG GPG key (644)

/etc/sudoers.d/postgres                   ← postgres NOPASSWD sudo (optional)
/var/lib/postgresql/.bashrc               ← postgres shell config (optional)
/var/lib/postgresql/.bash_profile         ← sources .bashrc (optional)
/var/lib/postgresql/.aliasrc              ← pgstart/pgstop/pgstatus (optional)
/var/lib/pgsql/bin/                       ← management scripts (optional)
  pstart.sh
  pstop.sh
  pstatus.sh
  psreload.sh
/usr/local/bin/pstart                     ← symlinks to management scripts
/usr/local/bin/pstop
/usr/local/bin/pstatus
/usr/local/bin/psreload
```

---

## Compatibility

| Feature | Ubuntu 22.04 (Jammy) | Ubuntu 24.04 (Noble) |
|---------|----------------------|----------------------|
| `/etc/os-release` detection | ✅ | ✅ |
| PGDG codename auto-detection | ✅ `jammy` | ✅ `noble` |
| `gpg --dearmor` + `signed-by` | ✅ | ✅ |
| `chmod 644` on keyring | ✅ harmless | ✅ required (`_apt` user) |
| `lsb_release` | ✅ installed | ⚠️ not installed by default — **not used** |
| `apt-key` | ⚠️ deprecated | ❌ removed — **not used** |
| `realpath` (coreutils) | ✅ | ✅ |
| `systemctl` | ✅ | ✅ |

The script will print a **warning** on Ubuntu 22.04:
```
[WARNING] This script is optimized for Ubuntu 24.04 (detected: 22.04)
```
Installation continues normally. No functional differences.

---

## Troubleshooting

### `apt-get update` fails after adding PGDG repo
The GPG keyring file must be world-readable (`644`). The install script sets
this explicitly. If you see permission errors from the `_apt` user:
```bash
chmod 644 /usr/share/keyrings/postgresql-keyring.gpg
```

### Optional steps silently skipped
`copy_management_files`, `configure_postgres_sudo`, and
`configure_postgres_environment` all run with `|| true` — they log a warning
and continue if they fail. Check the output for `[WARNING]` lines.

### Wrong version installed
Check which source won the priority chain:
```bash
# What does pg-config.env say?
cat ./pg-config.env

# Is PG_VERSION set in the environment?
echo $PG_VERSION

# Run with explicit version
sudo ./install_psql_U2404_v1-movedir.sh 16
```

### Service fails to start
If the symlink points to an empty or uninitialized directory, PostgreSQL cannot
start. The install script calls `initdb` only if needed. Check:
```bash
ls -la /var/lib/postgresql/13/main   # should be symlink → /db/mypg13
ls /db/mypg13/                        # should contain PG_VERSION, base/, etc.
systemctl status postgresql@13-main
journalctl -u postgresql@13-main --no-pager -n 50
```

### Uninstall leaves residue
Run `verify_uninstall` manually by re-running the uninstall script — it is
idempotent and will report on any remaining artifacts:
```bash
sudo ./uninstall_psql_U2404_v1-movedir.sh
```

---

## Author

**devesplabs**
Date: 2025-Jun-16
Last Modified: 2026-Apr-04 — ported to Ubuntu 24.04 (Noble Numbat)
