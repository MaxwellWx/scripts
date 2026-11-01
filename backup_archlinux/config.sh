#!/bin/bash
# Trusted configuration sourced as Bash code; no workflow actions here.
# Environment variables may override scalar defaults.

DOTFILES_DIR="${DOTFILES_DIR:-$HOME/dot_files}"
SCRIPTS_DIR="${SCRIPTS_DIR:-$HOME/scripts}"
BACKUP_STORAGE_ROOT="${BACKUP_STORAGE_ROOT:-$SCRIPTS_DIR/backup_archlinux}"
PUBLISHED_DIR="${PUBLISHED_DIR:-$SCRIPT_DIR/published}"
WEZTERM_DOTFILES_DIR="${WEZTERM_DOTFILES_DIR:-$DOTFILES_DIR/windows_configs/wezterm}"
LOCK_FILE="${LOCK_FILE:-$SCRIPT_DIR/.backup.lock}"

TARGET_USER="${TARGET_USER:-xuanwu}"
DOTFILES_REPO="${DOTFILES_REPO:-https://github.com/MaxwellWx/dot_files.git}"
SCRIPTS_REPO="${SCRIPTS_REPO:-https://github.com/MaxwellWx/scripts.git}"
AUR_HELPER_REPO="${AUR_HELPER_REPO:-https://aur.archlinux.org/yay-bin.git}"

# Explicit configuration takes precedence over inherited proxy settings.
PROXY_URL="${PROXY_URL:-${https_proxy:-${HTTPS_PROXY:-${http_proxy:-${HTTP_PROXY:-}}}}}"
SOCKS_URL="${SOCKS_URL:-${all_proxy:-${ALL_PROXY:-}}}"
REVIEW_PARENT="${REVIEW_PARENT:-/var/lib/backlinux/system-config-review}"
# Keep $repo and $arch literal for pacman.
PACMAN_MIRROR_URL="${PACMAN_MIRROR_URL:-}"
if [[ -z "$PACMAN_MIRROR_URL" ]]; then
  PACMAN_MIRROR_URL='https://mirrors.ustc.edu.cn/archlinux/$repo/os/$arch'
fi

PACMAN_PARALLEL_DOWNLOADS="${PACMAN_PARALLEL_DOWNLOADS:-3}"
PACMAN_DISABLE_DOWNLOAD_TIMEOUT="${PACMAN_DISABLE_DOWNLOAD_TIMEOUT:-1}"

SYSTEM_CONFIGS=(
  etc/pacman.conf
  etc/pacman.d/mirrorlist
  etc/makepkg.conf
)

OPTIONAL_SYSTEM_CONFIGS=(
  etc/wsl.conf
)

CHECK_DIRS=(
  "$DOTFILES_DIR"
  "$SCRIPTS_DIR"
  "$HOME/Code_Program"
  "$HOME/singularity_def_files"
)

REQUIRED_FILES=(
  pkg-lists/pkglist-pacman.txt
  pkg-lists/pkglist-aur.txt
  data/default_shell.txt
  data/sys_config.tar.gz
)

BOOTSTRAP_PACKAGES=(
  base-devel git stow sudo wget tar openssh gnupg
)

STOW_PACKAGES=(
  aria2 git nushell nvim rclone ssh topiary
)
