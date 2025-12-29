#!/bin/bash

DOTFILES_DIR="$HOME/dotfiles"
SCRIPTS_DIR="$HOME/scripts"
PKG_LIST_DIR="$SCRIPTS_DIR/backup_archlinux/pkg-lists"
DOTFILES_REPO="git@github.com:MaxwellWx/dot_files.git"

set -e # stop once encountering error

echo "[0/6] check keyring and basic pkgs"
sudo pacman -Sy --noconfirm archlinux-keyring
sudo pacman -Su --noconfirm
sudo pacman -S --needed --noconfirm git base-devel stow

echo "[1/6] check dot_files"
if [ ! -d "$DOTFILES_DIR" ]; then
  echo "dot_files dir does not exist,cloning"
  git clone "$DOTFILES_REPO" "$DOTFILES_DIR"
else
  echo "dot_files dir exist,skipping"
fi

echo "[2/6] check yay"
if ! command -v yay &>/dev/null; then
  echo "installing yay"
  cd /tmp
  git clone https://aur.archlinux.org/yay.git
  cd yay
  makepkg -si --noconfirm
  cd ~
  rm -rf /tmp/yay
else
  echo "yay installed"
fi

echo "[3/6] installing pkgs from pacman"
if [ -f "$PKG_LIST_DIR/pkglist-pacman.txt" ]; then
  sudo pacman -S --needed --noconfirm - <"$PKG_LIST_DIR/pkglist-pacman.txt"
else
  echo "error: pkglist_pacman.txt not found"
fi

echo "[4/6] installing pkgs from AUR"
if [ -f "$PKG_LIST_DIR/pkglist-aur.txt" ]; then
  yay -S --needed --noconfirm - <"$PKG_LIST_DIR/pkglist-aur.txt"
else
  echo "error: pkglist_aur.txt not found"
fi

echo "[5/6] stow config"
cd "$DOTFILES_DIR" || exit
for file in *; do
  [[ -d "$file" ]] || continue
  [[ "$file" == "pkg-lists" ]] && continue
  [[ "$file" == ".git" ]] && continue

  echo "stowing: $file"
  if ! stow "$file" 2>/dev/null; then
    echo "$file conflicting,back up old conifg"
    stow -R "$file"
  fi
done
stow --restow */

echo "[6/6] config default shell"
if command -v nu &>/dev/null; then
  CURRENT_SHELL=$(basename "$SHELL")
  if [ "$CURRENT_SHELL" != "nu" ]; then
    chsh -s "$(which nu)"
  fi
else
  echo "warning: nushell uninstalled,skipping"
fi

echo "restoring accomplished"
