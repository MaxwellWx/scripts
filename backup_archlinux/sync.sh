#!/bin/bash

set -Eeuo pipefail
umask 077

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/common.sh"
source "$SCRIPT_DIR/config.sh"

[[ "$EUID" -ne 0 ]] ||
  die "Run config synchronization as the normal target user"

APPLY=0

case "${1:-}" in
"")
  ;;
--apply)
  APPLY=1
  ;;
*)
  die "Usage: $0 [--apply]"
  ;;
esac

[[ $# -le 1 ]] ||
  die "Too many arguments"

require_commands git stow mktemp tar

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

if ((APPLY == 0)); then
  printf '\nPreview only. Review the changes, then run with --apply.\n'
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

printf 'Configuration synchronization completed.\n'
