#!/bin/bash

set -Eeuo pipefail
umask 077

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/common.sh"
source "$SCRIPT_DIR/config.sh"

[[ "$EUID" -ne 0 ]] ||
  die "Run config synchronization as the normal target user"

APPLY=1

case "${1:-}" in
"")
  ;;
--simulate | -n)
  APPLY=0
  ;;
*)
  die "Usage: $0 [--simulate|-n]"
  ;;
esac

[[ $# -le 1 ]] ||
  die "Too many arguments"

require_commands git stow mktemp tar rsync

[[ -d "$DOTFILES_DIR" ]] ||
  die "dot_files does not exist; use the fresh restore workflow first"

REPO_ROOT=$(git -C "$DOTFILES_DIR" rev-parse --show-toplevel)

[[ "$REPO_ROOT" == "$(cd -- "$DOTFILES_DIR" && pwd -P)" ]] ||
  die "DOTFILES_DIR must be the repository root"

[[ -z "$(git -C "$DOTFILES_DIR" status --porcelain)" ]] ||
  die "dot_files has local changes; commit or preserve them first"

BRANCH=$(git -C "$DOTFILES_DIR" symbolic-ref --quiet --short HEAD) ||
  die "dot_files is detached; explicitly switch to a tracking branch first"

UPSTREAM=$(git -C "$DOTFILES_DIR" rev-parse \
  --abbrev-ref --symbolic-full-name '@{upstream}') ||
  die "The current branch has no upstream"

REMOTE=$(git -C "$DOTFILES_DIR" config \
  --get "branch.$BRANCH.remote")

[[ -n "$REMOTE" && "$REMOTE" != "." ]] ||
  die "Expected a remote tracking branch"

git -C "$DOTFILES_DIR" fetch "$REMOTE"

OLD_COMMIT=$(git -C "$DOTFILES_DIR" rev-parse HEAD)
NEW_COMMIT=$(git -C "$DOTFILES_DIR" rev-parse "$UPSTREAM")

git -C "$DOTFILES_DIR" merge-base \
  --is-ancestor "$OLD_COMMIT" "$NEW_COMMIT" ||
  die "Local branch has commits outside upstream; merge them manually"

printf 'Current: %s\nTarget:  %s\n' "$OLD_COMMIT" "$NEW_COMMIT"

git -C "$DOTFILES_DIR" diff \
  --stat "$OLD_COMMIT" "$NEW_COMMIT"

sync_windows_configs() (
  set -Eeuo pipefail

  local simulate=$1
  local win_home staging name repo_path destination
  local -a options

  win_home=$(resolve_windows_home)

  if [[ -z "$win_home" ]]; then
    warn "Windows profile unavailable; Windows configuration deployment skipped"
    exit 0
  fi

  staging=$(mktemp -d)
  trap 'rm -rf -- "$staging"' EXIT

  for name in wezterm nushell; do
    repo_path="windows_configs/$name"

    if ! git -C "$DOTFILES_DIR" cat-file \
      -e "$NEW_COMMIT:$repo_path" 2>/dev/null; then
      warn "No tracked Windows configuration found: $repo_path"
      continue
    fi

    git -C "$DOTFILES_DIR" archive \
      "$NEW_COMMIT" -- "$repo_path" |
      tar -xf - -C "$staging"

    case "$name" in
    wezterm)
      destination="$win_home/.config/wezterm"
      ;;
    nushell)
      destination="$win_home/AppData/Roaming/nushell"
      ;;
    esac

    options=(-rc --mkpath --itemize-changes)

    if [[ "$name" == nushell ]]; then
      # Preserve history, plugin registries, and other runtime data.
      options+=(
        --include=/config.nu
        --include=/env.nu
        --include=/theme.nu
        --exclude='*'
      )
    else
      # Mirror the managed WezTerm configuration.
      options+=(--delete --exclude=.git)
    fi

    if ((simulate)); then
      options+=(--dry-run)
    else
      # Preserve files that will be overwritten or deleted.
      options+=(
        --backup
        "--backup-dir=$BACKUP_DIR/windows-$name"
      )
    fi

    printf '\nDeploying Windows %s: %s\n' "$name" "$destination"

    rsync "${options[@]}" \
      -- "$staging/$repo_path/" "$destination/"
  done
)

if ((APPLY == 0)); then
  sync_windows_configs 1

  printf '\nPreview completed. No configuration files were deployed.\n'
  printf 'Stow conflict checks will run during actual deployment.\n'
  exit 0
fi

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/backlinux"
mkdir -p -- "$STATE_DIR"

BACKUP_DIR=$(mktemp -d "$STATE_DIR/config-before.XXXXXXXX")

printf '%s\n' "$OLD_COMMIT" >"$BACKUP_DIR/dotfiles-commit.txt"

git -C "$DOTFILES_DIR" bundle create \
  "$BACKUP_DIR/dotfiles.bundle" HEAD

# Preserve existing managed paths, including their current symlinks.
MANAGED_PATHS=(
  .gitconfig
  .ssh/config
  .config/aria2
  .config/nushell
  .config/nvim
  .config/rclone
  .config/topiary
)

EXISTING_PATHS=()

for path in "${MANAGED_PATHS[@]}"; do
  if [[ -e "$HOME/$path" || -L "$HOME/$path" ]]; then
    EXISTING_PATHS+=("$path")
  fi
done

if ((${#EXISTING_PATHS[@]} > 0)); then
  tar -czf "$BACKUP_DIR/home-config.tar.gz" \
    -C "$HOME" -- "${EXISTING_PATHS[@]}"
fi

printf 'Backup: %s\n' "$BACKUP_DIR"

# Fast-forward to the exact commit shown above.
git -C "$DOTFILES_DIR" merge --ff-only "$NEW_COMMIT"

if ! stow \
  --dir="$DOTFILES_DIR" \
  --target="$HOME" \
  --simulate \
  --restow "${STOW_PACKAGES[@]}"; then

  printf 'Stow conflicts detected. Returning tracked files to the previous commit.\n' >&2

  git -C "$DOTFILES_DIR" reset --keep "$OLD_COMMIT" ||
    warn "Automatic rollback failed; inspect the repository before continuing"

  die "Configuration deployment stopped"
fi

stow \
  --dir="$DOTFILES_DIR" \
  --target="$HOME" \
  --restow "${STOW_PACKAGES[@]}"

sync_windows_configs 0

printf 'Configuration synchronization completed.\n'
