#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# Define core directories
DOTFILES_DIR="$HOME/dot_files"
SCRIPTS_DIR="$HOME/scripts"
BACKUP_ROOT="$SCRIPTS_DIR/backup_archlinux"
PKG_LIST_DIR="$BACKUP_ROOT/pkg-lists"
DATA_DIR="$BACKUP_ROOT/data"

# Ensure backup directories exist
mkdir -p "$PKG_LIST_DIR" "$DATA_DIR"

echo "=== Arch Linux WSL Backup Pipeline ==="

echo "[1/5] Backup pkgs from pacman..."
pacman -Qqen >"$PKG_LIST_DIR/pkglist-pacman.txt"

echo "[2/5] Backup pkgs from AUR..."
pacman -Qqem >"$PKG_LIST_DIR/pkglist-aur.txt"

echo "[3/5] Archive sensitive credentials (.ssh, .gnupg)..."
SENSITIVE_DIRS=()
[ -d "$HOME/.ssh" ] && SENSITIVE_DIRS+=(".ssh")
[ -d "$HOME/.gnupg" ] && SENSITIVE_DIRS+=(".gnupg")

if [ ${#SENSITIVE_DIRS[@]} -gt 0 ]; then
  # Use -C to change to $HOME before archiving to prevent absolute path nesting
  tar -czf "$DATA_DIR/secure_data.tar.gz" -C "$HOME" "${SENSITIVE_DIRS[@]}"

  # Added loopback mode to force inline password prompt in WSL
  gpg --pinentry-mode loopback --symmetric --cipher-algo AES256 --output "$DATA_DIR/secure_data.tar.gz.gpg" "$DATA_DIR/secure_data.tar.gz"
  rm "$DATA_DIR/secure_data.tar.gz"
  echo "  -> Credentials archived to $DATA_DIR/secure_data.tar.gz.gpg"
else
  echo "  -> No credentials found to archive."
fi

echo "[4/5] Archive system configuration files..."
tar -czf "$DATA_DIR/sys_config.tar.gz" -C / etc/pacman.conf etc/pacman.d/mirrorlist etc/makepkg.conf 2>/dev/null || true
echo "  -> System configs archived to $DATA_DIR/sys_config.tar.gz"

echo "[5/5] Check git status of core directories..."
CHECK_DIRS=(
  "$DOTFILES_DIR"
  "$SCRIPTS_DIR"
  "$HOME/Code_Program"
  "$HOME/singularity_def_files"
)

for dir in "${CHECK_DIRS[@]}"; do
  if [ -d "$dir/.git" ]; then
    cd "$dir" || exit
    if [[ -n $(git status -s) ]]; then
      echo "  [Warning] Uncommitted changes detected in $dir"
      git status -s | sed 's/^/    /'
    fi
  elif [ -d "$dir" ]; then
    echo "  [Notice] $dir is not a git repository. It will not be synced."
  fi
done

echo "=== Backup Accomplished ==="
