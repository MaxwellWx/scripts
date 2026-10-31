# Arch Linux WSL backup and restore

- `backup.sh`: collect package lists, credentials, system configuration and optional Windows WezTerm configuration; publish a snapshot.
- `restore.sh`: verify an explicit snapshot, bootstrap packages, configure an interactive user and sudo, then restore selected content.
- `common.sh`: shared logging, command checks, target-user execution and Windows profile discovery.
- `config.sh`: trusted Bash configuration containing defaults and package/file lists. Loading it does not run backup or restore steps.

Run the entry scripts with Bash. Keep all four shell files together; the entry scripts resolve their helpers relative to their own location.

```bash
bash /path/to/backup_archlinux/backup.sh
sudo bash /path/to/backup_archlinux/restore.sh /path/to/snapshot
sudo bash /path/to/backup_archlinux/restore.sh /path/to/snapshot --skip-credentials
```

Restore is interactive: newly created users receive a password prompt, and sudo authentication is checked as the target user. Existing credential directories are refused unless credential restoration is explicitly skipped.

Edit `config.sh` to change file/package lists. Scalar defaults can also be overridden with environment variables, for example:

```bash
BACKUP_STORAGE_ROOT="$HOME/.local/state/backlinux" bash /path/to/backup_archlinux/backup.sh
sudo TARGET_USER=xuanwu bash /path/to/backup_archlinux/restore.sh /path/to/snapshot
```

`BACKUP_STORAGE_ROOT` controls where backups are written; restore always reads the snapshot passed on the command line. System configuration review files go to `REVIEW_PARENT`. Repository checks currently report local changes; they do not back up repository contents or unpushed commits.

Syntax validation:

```bash
bash -n backup.sh restore.sh common.sh config.sh
```

Full restoration should be exercised in a disposable Arch WSL instance.
