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

echo "[1/4] Backup pkgs from pacman..."
pacman -Qqen >"$PKG_LIST_DIR/pkglist-pacman.txt"

echo "[2/4] Backup pkgs from AUR..."
pacman -Qqem >"$PKG_LIST_DIR/pkglist-aur.txt"

echo "[3/4] Archive sensitive credentials (.ssh, .gnupg)..."
SENSITIVE_DIRS=()
[ -d "$HOME/.ssh" ] && SENSITIVE_DIRS+=(".ssh")

if [ ${#SENSITIVE_DIRS[@]} -gt 0 ]; then
  # Use -C to change to $HOME before archiving to prevent absolute path nesting
  tar -czf "$DATA_DIR/secure_data.tar.gz" -C "$HOME" "${SENSITIVE_DIRS[@]}"
  echo "  -> Credentials archived to $DATA_DIR/secure_data.tar.gz"
  echo "  -> WARNING: Ensure your backup repository is set to PRIVATE."
else
  echo "  -> No credentials found to archive."
fi

echo "[4/4] Check git status of core directories..."
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
