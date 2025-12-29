#!/bin/bash

DOTFILES_DIR="$HOME/dot_files"
SCRIPTS_DIR="$HOME/scripts"
BACKUP_DIR="$SCRIPTS_DIR/backup_archlinux/pkg-lists"
mkdir -p "$BACKUP_DIR"

echo "[1/3] backup pkgs from pacman"
pacman -Qqen >"$BACKUP_DIR/pkglist-pacman.txt"

echo "[2/3] backup pkgs from AUR"
pacman -Qqem >"$BACKUP_DIR/pkglist-aur.txt"

echo "[3/3] check git status of dot_files"
if [ -d "$DOTFILES_DIR/.git" ]; then
  cd "$DOTFILES_DIR" || exit
  if [[ -n $(git status -s) ]]; then
    echo "warning: not-submitted changes in $DOTFILES_DIR"
    git status -s
  else
    echo ""
  fi
else
  echo "warning: $DOTFILES_DIR is not a git repository"
fi

echo "backup accomplished"
