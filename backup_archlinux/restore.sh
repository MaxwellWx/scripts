#!/bin/bash

set -Eeuo pipefail
umask 077

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/common.sh"
source "$SCRIPT_DIR/config.sh"

trap 'printf "Error: failed at line %s\n" "$LINENO" >&2' ERR

usage() {
  cat <<'EOF'
Usage:
  restore.sh [--latest] [--skip-credentials]
  restore.sh SNAPSHOT_DIRECTORY [--skip-credentials]

Without a snapshot directory, restore from published/latest.tar.gz.
Run as root in an interactive terminal.
EOF
}

SKIP_CREDENTIALS=0
SNAPSHOT_ARG=""
LATEST_REQUESTED=0

while (($# > 0)); do
  case "$1" in
  --latest)
    LATEST_REQUESTED=1
    ;;
  --skip-credentials)
    SKIP_CREDENTIALS=1
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  --*)
    die "Unknown option: $1"
    ;;
  *)
    [[ -z "$SNAPSHOT_ARG" ]] ||
      die "Only one snapshot directory may be specified"

    SNAPSHOT_ARG=$1
    ;;
  esac

  shift
done

if ((LATEST_REQUESTED)) && [[ -n "$SNAPSHOT_ARG" ]]; then
  die "Do not combine --latest with a snapshot directory"
fi

[[ "$EUID" -eq 0 ]] ||
  die "Run this script as root"

[[ -t 0 && -t 1 ]] ||
  die "Restore requires an interactive terminal"

[[ "$TARGET_USER" =~ ^[a-z_][a-z0-9_-]*$ ]] ||
  die "Unsupported target username: $TARGET_USER"

[[ "$TARGET_USER" != root ]] ||
  die "The target user must not be root"

restore_from_published() (
  set -Eeuo pipefail
  umask 077

  local import_dir=""
  local status
  local -a restore_args=()

  [[ -f "$PUBLISHED_DIR/latest.tar.gz" ]] ||
    die "Published archive not found: $PUBLISHED_DIR/latest.tar.gz"

  [[ -s "$PUBLISHED_DIR/SHA256SUMS" ]] ||
    die "Published checksum manifest is missing"

  require_commands tar sha256sum mktemp flock

  # Read a consistent publication while backup/publish are not writing it.
  exec 8>"$LOCK_FILE"
  flock -s -n 8 ||
    die "Backup or publication is running; retry later"

  (
    cd -- "$PUBLISHED_DIR"
    sha256sum --check --strict SHA256SUMS
  ) || die "Published archive verification failed"

  import_dir=$(mktemp -d /var/tmp/backlinux-import.XXXXXXXX)

  trap '
    status=$?

    if ((status == 0)); then
      rm -rf -- "$import_dir"
    else
      printf "Restore failed. Import files retained at: %s\n" \
        "$import_dir" >&2
    fi
  ' EXIT

  mkdir "$import_dir/snapshot"

  tar \
    --extract \
    --gzip \
    --file="$PUBLISHED_DIR/latest.tar.gz" \
    --directory="$import_dir/snapshot" \
    --no-same-owner \
    --no-same-permissions

  # The publication has been copied into the private import directory.
  flock -u 8
  exec 8>&-

  [[ -f "$import_dir/snapshot/COMPLETE" ]] ||
    die "Published snapshot has no COMPLETE marker"

  [[ -s "$import_dir/snapshot/SHA256SUMS" ]] ||
    die "Published snapshot has no checksum manifest"

  (
    cd -- "$import_dir/snapshot"
    sha256sum --check --strict SHA256SUMS
  ) || die "Extracted snapshot verification failed"

  echo "Configuring pacman downloads before package installation..."
  configure_pacman_downloads

  # Existing restore preflight requires GnuPG.
  if ! command -v gpg >/dev/null 2>&1; then
    require_commands pacman
    pacman -Syu --needed gnupg
  fi

  restore_args=("$import_dir/snapshot")

  if ((SKIP_CREDENTIALS)); then
    restore_args+=(--skip-credentials)
  fi

  echo "Snapshot prepared. Starting restore..."

  cd /tmp

  bash "$SCRIPT_DIR/restore.sh" "${restore_args[@]}"
)

# No directory means: prepare and restore the bundled publication.
if [[ -z "$SNAPSHOT_ARG" ]]; then
  restore_from_published
  exit 0
fi

TARGET_HOME=""
TARGET_GROUP=""

require_commands \
  realpath sha256sum tar gpg getent \
  pacman pacman-key runuser passwd useradd

BACKUP_ROOT=$(realpath -- "$SNAPSHOT_ARG")

[[ -d "$BACKUP_ROOT" ]] ||
  die "Snapshot directory not found"

[[ -f "$BACKUP_ROOT/COMPLETE" ]] ||
  die "Snapshot is incomplete or uses an unsupported legacy format"

[[ -s "$BACKUP_ROOT/SHA256SUMS" ]] ||
  die "Checksum manifest is missing or empty"

for file in "${REQUIRED_FILES[@]}"; do
  [[ -f "$BACKUP_ROOT/$file" ]] ||
    die "Required snapshot file is missing: $file"
done

[[ -s "$BACKUP_ROOT/pkg-lists/pkglist-pacman.txt" ]] ||
  die "Official package list is empty"

(
  cd -- "$BACKUP_ROOT"
  sha256sum --check SHA256SUMS
) || die "Snapshot verification failed"
echo "Configuring pacman downloads before package installation..."
configure_pacman_downloads

echo "=== Arch Linux WSL Restore Pipeline ==="
printf 'Snapshot: %s\n' "$BACKUP_ROOT"
printf 'Target user: %s\n' "$TARGET_USER"

echo "[0/10] Stage system configurations for review..."

mkdir -p -- "$REVIEW_PARENT"

SYSTEM_CONFIG_REVIEW_DIR=$(mktemp -d "$REVIEW_PARENT/review.XXXXXXXX")

tar -xzf "$BACKUP_ROOT/data/sys_config.tar.gz" \
  -C "$SYSTEM_CONFIG_REVIEW_DIR"

printf '  -> Saved configuration files: %s\n' \
  "$SYSTEM_CONFIG_REVIEW_DIR"

warn "Review and merge these files separately; system files were not replaced"

echo "[1/10] Configure System Locale (UTF-8)..."
if grep -q "^#en_US.UTF-8 UTF-8" /etc/locale.gen; then
  sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
  locale-gen
  echo "LANG=en_US.UTF-8" >/etc/locale.conf
  echo "  -> Locale generated and set to en_US.UTF-8."
else
  echo "  -> Locale already configured."
fi

echo "[2/10] Initialize keyring and basic pkgs..."
if [ ! -d "/etc/pacman.d/gnupg" ]; then
  pacman-key --init
  pacman-key --populate archlinux
  echo "  -> Pacman keyring initialized."
else
  echo "  -> Pacman keyring already exists. Skipping initialization."
fi
pacman -Sy --noconfirm archlinux-keyring
pacman -Su --noconfirm
pacman -S --needed --noconfirm "${BOOTSTRAP_PACKAGES[@]}"

echo "[3/10] Configure target user and interactive sudo..."

require_commands sudo visudo install id cut

[[ -t 0 && -t 1 ]] ||
  die "Interactive user setup requires a terminal"

NEW_USER=0

if ! id "$TARGET_USER" >/dev/null 2>&1; then
  useradd -m -s /bin/bash "$TARGET_USER"
  NEW_USER=1
fi

TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
TARGET_GROUP=$(id -gn "$TARGET_USER")

[[ "$TARGET_HOME" == /* && "$TARGET_HOME" != / ]] ||
  die "Invalid target home: $TARGET_HOME"

[[ -d "$TARGET_HOME" ]] ||
  die "Target home does not exist: $TARGET_HOME"

if ((NEW_USER)); then
  printf '\nSet the login password for %s.\n' "$TARGET_USER"
  passwd "$TARGET_USER"
fi

# Install a password-required sudo rule for this user only.
(
  sudoers_tmp=$(mktemp)
  trap 'rm -f -- "$sudoers_tmp"' EXIT

  printf '%s ALL=(ALL:ALL) PASSWD: ALL\n' \
    "$TARGET_USER" >"$sudoers_tmp"

  visudo -cf "$sudoers_tmp"

  install \
    -o root \
    -g root \
    -m 0440 \
    "$sudoers_tmp" \
    "/etc/sudoers.d/90-backlinux-$TARGET_USER"
)

visudo -c

printf '\nVerify sudo access using the password for %s.\n' \
  "$TARGET_USER"

# Clear a previous timestamp so this step really checks authentication.
as_target sudo -k

as_target sudo -v ||
  die "Sudo authentication failed. Check the target user's password and sudo policy"

printf '\nWSL default-user setting, if needed:\n'
printf '[user]\ndefault=%s\n' "$TARGET_USER"

echo "[4/10] Keep snapshot at its original location..."

echo "[5/10] Restore sensitive credentials..."

SECURE_ARCHIVE="$BACKUP_ROOT/data/secure_data.tar.gz.gpg"

if ((SKIP_CREDENTIALS)); then
  warn "Credential restoration explicitly skipped"
elif [[ -f "$SECURE_ARCHIVE" ]]; then
  # Refuse to overwrite existing credentials.
  for name in .ssh .gnupg; do
    [[ ! -e "$TARGET_HOME/$name" && ! -L "$TARGET_HOME/$name" ]] ||
      die "Credential destination already exists: $TARGET_HOME/$name"
  done

  restore_tmp=$(mktemp -d)
  chmod 700 "$restore_tmp"
  trap 'rm -rf -- "$restore_tmp"' EXIT

  # Decrypt fully before extraction, so a failed decrypt cannot
  # partially overwrite the target home.
  gpg \
    --pinentry-mode loopback \
    --decrypt \
    --output "$restore_tmp/credentials.tar.gz" \
    "$SECURE_ARCHIVE"

  mkdir "$restore_tmp/unpacked"

  tar \
    --extract \
    --gzip \
    --file="$restore_tmp/credentials.tar.gz" \
    --directory="$restore_tmp/unpacked" \
    --no-same-owner \
    --no-same-permissions

  for name in .ssh .gnupg; do
    source_dir="$restore_tmp/unpacked/$name"

    [[ -d "$source_dir" && ! -L "$source_dir" ]] || continue

    cp -a -- "$source_dir" "$TARGET_HOME/$name"
    chown -hR "$TARGET_USER:$TARGET_GROUP" "$TARGET_HOME/$name"

    find "$TARGET_HOME/$name" -type d -exec chmod 700 {} +
    find "$TARGET_HOME/$name" -type f -exec chmod 600 {} +
  done

  rm -rf -- "$restore_tmp"
  trap - EXIT

  echo "  -> Credentials restored."
else
  echo "  -> No credential archive. Skipping."
fi

echo "[6/10] Install pkgs from pacman..."
PKG_LIST_DIR="$BACKUP_ROOT/pkg-lists"
if [ -f "$PKG_LIST_DIR/pkglist-pacman.txt" ]; then
  pacman -S --needed --noconfirm - <"$PKG_LIST_DIR/pkglist-pacman.txt"
else
  die "pkglist-pacman.txt not found"
fi

echo "[7/10] Deploy AUR helper..."

as_target bash -s -- "$TARGET_HOME" "$AUR_HELPER_REPO" <<'BASH'
set -Eeuo pipefail

cd -- "$1"

if command -v yay >/dev/null 2>&1; then
  echo "  -> yay is already installed."
  exit 0
fi

build_dir=$(mktemp -d /tmp/backlinux-yay.XXXXXXXX)
trap 'rm -rf -- "$build_dir"' EXIT

git clone \
  "$2" \
  "$build_dir/yay-bin"

cd -- "$build_dir/yay-bin"
makepkg -si --noconfirm
BASH

echo "[8/10] Install foreign packages..."

PKG_LIST_DIR="$BACKUP_ROOT/pkg-lists"
AUR_PACKAGES=()

while IFS= read -r pkg || [[ -n "$pkg" ]]; do
  pkg=${pkg%%#*}
  pkg=${pkg#"${pkg%%[![:space:]]*}"}
  pkg=${pkg%"${pkg##*[![:space:]]}"}

  [[ -n "$pkg" ]] || continue

  [[ "$pkg" =~ ^[a-zA-Z0-9@_+][a-zA-Z0-9@._+-]*$ ]] ||
    die "Invalid package name: $pkg"

  case "$pkg" in
  yay | yay-bin)
    continue
    ;;
  topiary)
    pkg=topiary-bin
    ;;
  esac

  AUR_PACKAGES+=("$pkg")
done <"$PKG_LIST_DIR/pkglist-aur.txt"

if ((${#AUR_PACKAGES[@]} > 0)); then
  as_target yay \
    -S --needed --noconfirm -- "${AUR_PACKAGES[@]}"
else
  echo "  -> No foreign packages to install."
fi

echo "[9/10] Prepare repositories and deploy dotfiles..."

ensure_repository() {
  local url=$1
  local destination=$2
  local actual_url

  if [[ ! -e "$destination" ]]; then
    as_target git clone -- "$url" "$destination"
    return
  fi

  as_target git -C "$destination" rev-parse \
    --is-inside-work-tree >/dev/null ||
    die "Existing path is not a Git repository: $destination"

  actual_url=$(as_target git -C "$destination" remote get-url origin)

  [[ "$actual_url" == "$url" ]] ||
    die "Unexpected origin in $destination: $actual_url"

  if [[ -n "$(as_target git -C "$destination" status --porcelain)" ]]; then
    die "Repository contains local changes: $destination"
  fi

  echo "  -> Keeping existing repository: $destination"
}

ensure_repository "$DOTFILES_REPO" "$TARGET_HOME/dot_files"
ensure_repository "$SCRIPTS_REPO" "$TARGET_HOME/scripts"

DOTFILES_COMMIT_FILE="$BACKUP_ROOT/data/dotfiles-commit.txt"

if [[ -f "$DOTFILES_COMMIT_FILE" ]]; then
  DOTFILES_COMMIT=$(<"$DOTFILES_COMMIT_FILE")

  [[ "$DOTFILES_COMMIT" =~ ^[0-9a-f]{40}$ ]] ||
    die "Invalid dotfiles commit"

  as_target git -C "$TARGET_HOME/dot_files" \
    fetch origin "$DOTFILES_COMMIT"

  as_target git -C "$TARGET_HOME/dot_files" \
    checkout --detach "$DOTFILES_COMMIT"
else
  warn "Legacy snapshot: dotfiles version is not pinned"
fi

as_target stow \
  --dir="$TARGET_HOME/dot_files" \
  --target="$TARGET_HOME" \
  --simulate \
  --restow \
  -- "${STOW_PACKAGES[@]}"

as_target stow \
  --dir="$TARGET_HOME/dot_files" \
  --target="$TARGET_HOME" \
  --restow \
  -- "${STOW_PACKAGES[@]}"

echo "[-] Restore Windows WezTerm configuration..."

WEZTERM_ARCHIVE="$BACKUP_ROOT/data/wezterm.tar.gz"
WIN_HOME=""

if [[ -f "$WEZTERM_ARCHIVE" ]]; then
  WIN_HOME=$(resolve_windows_home)

  if [[ -n "$WIN_HOME" ]]; then
    # Run from an accessible directory, and pass paths as arguments.
    (
      transfer_dir=$(mktemp -d "$TARGET_HOME/.backlinux-transfer.XXXXXXXX")
      trap 'rm -rf -- "$transfer_dir"' EXIT

      install \
        -o "$TARGET_USER" \
        -g "$TARGET_GROUP" \
        -m 0600 \
        "$WEZTERM_ARCHIVE" \
        "$transfer_dir/wezterm.tar.gz"

      chown "$TARGET_USER:$TARGET_GROUP" "$transfer_dir"
      chmod 700 "$transfer_dir"

      cd -- "$TARGET_HOME"

      as_target bash -s -- \
        "$WIN_HOME" \
        "$transfer_dir/wezterm.tar.gz" <<'BASH'
set -Eeuo pipefail

win_home=$1
archive=$2

parent="$win_home/.config"
destination="$parent/wezterm"

mkdir -p -- "$parent"

staging=$(mktemp -d "$parent/.wezterm-restore.XXXXXXXX")
trap 'rm -rf -- "$staging"' EXIT

mkdir "$staging/config"

tar -xzf "$archive" \
  -C "$staging/config" \
  --no-same-owner \
  --no-same-permissions

previous=""

if [[ -e "$destination" || -L "$destination" ]]; then
  previous=$(mktemp -d "$parent/wezterm.previous.XXXXXXXX")
  rmdir -- "$previous"

  mv -- "$destination" "$previous"
fi

if ! mv -- "$staging/config" "$destination"; then
  if [[ -n "$previous" ]]; then
    mv -- "$previous" "$destination" ||
      printf 'Error: rollback failed; previous config: %s\n' \
        "$previous" >&2
  fi

  exit 1
fi

printf '  -> WezTerm restored to %s\n' "$destination"

if [[ -n "$previous" ]]; then
  printf '  -> Previous configuration retained at %s\n' "$previous"
fi
BASH
    )
  else
    warn "Windows profile unavailable; WezTerm restoration skipped"
  fi
else
  warn "Snapshot contains no WezTerm archive"
fi

echo "[10/10] Restore default shell configuration..."
SHELL_FILE="$BACKUP_ROOT/data/default_shell.txt"

if [ -f "$SHELL_FILE" ]; then
  TARGET_SHELL=$(cat "$SHELL_FILE" | tr -d '[:space:]')

  if [ -n "$TARGET_SHELL" ] && [ -x "$TARGET_SHELL" ]; then
    if ! grep -Fxq "$TARGET_SHELL" /etc/shells; then
      echo "$TARGET_SHELL" >>/etc/shells
    fi
    chsh -s "$TARGET_SHELL" "$TARGET_USER"
    echo "  -> Default shell successfully changed to $TARGET_SHELL."
  else
    echo "  -> Warning: Executable target shell not found or invalid."
  fi
fi

echo "=== Restore Accomplished ==="
