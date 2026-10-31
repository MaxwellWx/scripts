#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -Eeuo pipefail
umask 077

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/common.sh"
source "$SCRIPT_DIR/config.sh"

trap 'printf "Error: failed at line %s\n" "$LINENO" >&2' ERR

BACKUP_ROOT="$BACKUP_STORAGE_ROOT"

require_commands pacman tar gpg getent cut mktemp flock sha256sum

mkdir -p -- "$BACKUP_ROOT"

# Prevent concurrent backups from publishing mixed results.
exec 9>"$BACKUP_ROOT/.backup.lock"
flock -n 9 || die "Another backup is running"

# Generate all files here first. Existing backup files remain untouched.
WORK_DIR=$(mktemp -d "$BACKUP_ROOT/.pending.XXXXXXXX")
trap 'rm -rf -- "$WORK_DIR"' EXIT

PKG_LIST_DIR="$WORK_DIR/pkg-lists"
DATA_DIR="$WORK_DIR/data"

mkdir -p -- "$PKG_LIST_DIR" "$DATA_DIR"

echo "=== Arch Linux WSL Backup Pipeline ==="

echo "[1/7] Backup explicitly installed official packages..."
pacman -Qqen >"$PKG_LIST_DIR/pkglist-pacman.txt"

echo "[2/7] Backup explicitly installed foreign packages..."

# Query all explicit packages first, so an empty foreign set is valid
# without suppressing failures from the package database query.
pacman -Qqe >"$WORK_DIR/explicit-packages.txt"

: >"$PKG_LIST_DIR/pkglist-aur.txt"

while IFS= read -r pkg; do
  [[ -n "$pkg" ]] || continue

  if pacman -Qn -- "$pkg" >/dev/null 2>&1; then
    continue
  fi

  pacman -Q -- "$pkg" >/dev/null ||
    die "Package disappeared during backup: $pkg"

  printf '%s\n' "$pkg" >>"$PKG_LIST_DIR/pkglist-aur.txt"
done <"$WORK_DIR/explicit-packages.txt"

echo "[3/7] Archive sensitive credentials (.ssh, .gnupg)..."
SENSITIVE_DIRS=()
[ -d "$HOME/.ssh" ] && SENSITIVE_DIRS+=(".ssh")
[ -d "$HOME/.gnupg" ] && SENSITIVE_DIRS+=(".gnupg")

if ((${#SENSITIVE_DIRS[@]} > 0)); then
  tar \
    --exclude='.ssh/config' \
    --exclude='.gnupg/S.gpg-agent*' \
    --exclude='.gnupg/S.dirmngr' \
    -czf - -C "$HOME" -- "${SENSITIVE_DIRS[@]}" |
    gpg \
      --pinentry-mode loopback \
      --symmetric \
      --cipher-algo AES256 \
      --output "$DATA_DIR/secure_data.tar.gz.gpg"

  echo "  -> Credentials encrypted."
else
  echo "  -> No credentials found to archive."
fi

echo "[4/7] Archive system configuration files..."
for file in "${SYSTEM_CONFIGS[@]}"; do
  [[ -r "/$file" ]] ||
    die "Cannot read system configuration: /$file"
done

tar -czf "$DATA_DIR/sys_config.tar.gz" \
  -C / -- "${SYSTEM_CONFIGS[@]}"

tar -tzf "$DATA_DIR/sys_config.tar.gz" >/dev/null

echo "  -> System configs archived to $DATA_DIR/sys_config.tar.gz"

echo "[5/7] Archive default shell configuration..."
DEFAULT_SHELL=$(getent passwd "$(id -un)" | cut -d: -f7)

[[ "$DEFAULT_SHELL" == /* && -x "$DEFAULT_SHELL" ]] ||
  die "Invalid default shell: $DEFAULT_SHELL"

printf '%s\n' "$DEFAULT_SHELL" >"$DATA_DIR/default_shell.txt"

echo "  -> Default shell ($(cat "$DATA_DIR/default_shell.txt")) recorded."

echo "[6/7] Backup Windows WezTerm configuration..."

WIN_HOME=$(resolve_windows_home)

printf 'skipped\n' >"$DATA_DIR/wezterm-status.txt"

if [[ -n "$WIN_HOME" ]]; then
  WEZTERM_WIN_DIR="$WIN_HOME/.config/wezterm"

  if [[ -d "$WEZTERM_WIN_DIR" ]]; then
    tar -czf "$DATA_DIR/wezterm.tar.gz" \
      -C "$WEZTERM_WIN_DIR" .

    tar -tzf "$DATA_DIR/wezterm.tar.gz" >/dev/null

    printf 'included\n' >"$DATA_DIR/wezterm-status.txt"
    echo "  -> WezTerm configuration archived."
  else
    warn "WezTerm directory not found: $WEZTERM_WIN_DIR"
  fi
else
  warn "Windows profile unavailable; skipping WezTerm"
fi

echo "[7/7] Check git status of core directories..."
for dir in "${CHECK_DIRS[@]}"; do
  if [ -d "$dir/.git" ]; then
    cd "$dir" || exit
    if [[ -n $(git status -s) ]]; then
      echo "  [Warning] Uncommitted changes detected in $dir."
      echo "  >>> PLEASE COMMIT AND PUSH THESE CHANGES TO PREVENT DATA LOSS <<<"
      git status -s | sed 's/^/    /'
    fi
  elif [ -d "$dir" ]; then
    echo "  [Notice] $dir is not a git repository. It will not be synced."
  fi
done

echo "Publishing backup..."

# Publish a complete generation as a separate directory.
SNAPSHOT_ID="$(date -u +%Y%m%dT%H%M%SZ)-${WORK_DIR##*.pending.}"
SNAPSHOT_DIR="$BACKUP_ROOT/snapshots/$SNAPSHOT_ID"

mkdir -p -- "$BACKUP_ROOT/snapshots"

(
  cd -- "$WORK_DIR"
  sha256sum \
    pkg-lists/pkglist-pacman.txt \
    pkg-lists/pkglist-aur.txt \
    data/default_shell.txt \
    data/sys_config.tar.gz \
    >SHA256SUMS

  sha256sum data/wezterm-status.txt >>SHA256SUMS

  if [[ -f data/secure_data.tar.gz.gpg ]]; then
    sha256sum data/secure_data.tar.gz.gpg >>SHA256SUMS
  fi

  if [[ -f data/wezterm.tar.gz ]]; then
    sha256sum data/wezterm.tar.gz >>SHA256SUMS
  fi

  sha256sum --check SHA256SUMS
)

touch "$WORK_DIR/COMPLETE"
mv -T -- "$WORK_DIR" "$SNAPSHOT_DIR"
trap - EXIT

echo "=== Backup Accomplished ==="
printf 'Snapshot: %s\n' "$SNAPSHOT_DIR"
