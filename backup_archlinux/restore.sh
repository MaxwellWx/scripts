#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# Core configurations
TARGET_USER="xuanwu"
TARGET_HOME="/home/$TARGET_USER"
DOTFILES_REPO="https://github.com/MaxwellWx/dot_files.git"

# Intercept check: Must be executed as root
if [ "$EUID" -ne 0 ]; then
  echo "Error: This restore pipeline MUST be executed as root."
  exit 1
fi

echo "=== Arch Linux WSL Restore Pipeline ==="

# --- 动态路径解析机制 ---
# 无论脚本被放置在何处，通过探测 data 目录准确定位 BACKUP_ROOT
SCRIPT_DIR=$(dirname "$(realpath "$0")")
if [ -d "$SCRIPT_DIR/data" ]; then
  BACKUP_ROOT="$SCRIPT_DIR"
elif [ -d "$SCRIPT_DIR/backup_archlinux/data" ]; then
  BACKUP_ROOT="$SCRIPT_DIR/backup_archlinux"
else
  echo "Error: Cannot locate backup data directory (expected 'data' or 'backup_archlinux/data')."
  exit 1
fi
echo "  -> Resolved BACKUP_ROOT: $BACKUP_ROOT"

echo "[0/8] Restore system configurations..."
if [ -f "$BACKUP_ROOT/data/sys_config.tar.gz" ]; then
  tar -xzf "$BACKUP_ROOT/data/sys_config.tar.gz" -C /
  echo "  -> System configs (pacman.conf, mirrorlist) restored."
else
  echo "  -> Warning: sys_config.tar.gz not found. Skipping."
fi

echo "[1/8] Initialize keyring and basic pkgs..."
pacman-key --init
pacman-key --populate archlinux
pacman -Sy --noconfirm archlinux-keyring
pacman -Su --noconfirm
# Added gnupg to ensure decryption tool is strictly present
pacman -S --needed --noconfirm base-devel git stow sudo wget tar openssh gnupg

echo "[2/8] Setup target user ($TARGET_USER) and privileges..."
if ! id "$TARGET_USER" &>/dev/null; then
  useradd -m -G wheel -s /bin/bash "$TARGET_USER"
  # Configure passwordless sudo for the wheel group
  echo "%wheel ALL=(ALL:ALL) NOPASSWD: ALL" >/etc/sudoers.d/wheel_nopasswd
fi

# Write WSL config to set default user for next boot
cat <<EOF >/etc/wsl.conf
[user]
default=$TARGET_USER
EOF

echo "[3/8] Migrate restore scripts and data..."
# Safely migrate data into the target user's home domain
if [[ "$BACKUP_ROOT" != "$TARGET_HOME"* ]]; then
  echo "  -> Migrating repository to $TARGET_HOME..."
  TARGET_BACKUP_ROOT="$TARGET_HOME/backup_archlinux"
  cp -r "$BACKUP_ROOT" "$TARGET_BACKUP_ROOT"
  chown -R "$TARGET_USER:$TARGET_USER" "$TARGET_BACKUP_ROOT"
  BACKUP_ROOT="$TARGET_BACKUP_ROOT"
fi

echo "[4/8] Restore sensitive credentials (SSH & GPG)..."
if [ -f "$BACKUP_ROOT/data/secure_data.tar.gz.gpg" ]; then
  # loopback mode is strictly required to prevent failure in headless/WSL environments
  gpg --pinentry-mode loopback --decrypt --output "$BACKUP_ROOT/data/secure_data.tar.gz" "$BACKUP_ROOT/data/secure_data.tar.gz.gpg"
  tar -xzf "$BACKUP_ROOT/data/secure_data.tar.gz" -C "$TARGET_HOME/"
  rm "$BACKUP_ROOT/data/secure_data.tar.gz"

  # Strictly enforce ownership and secure permissions
  chown -R "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.ssh" "$TARGET_HOME/.gnupg" 2>/dev/null || true
  chmod 700 "$TARGET_HOME/.ssh" "$TARGET_HOME/.gnupg" 2>/dev/null || true
  find "$TARGET_HOME/.ssh" -type f -exec chmod 600 {} \; 2>/dev/null || true
  find "$TARGET_HOME/.ssh" -type f -name "*.pub" -exec chmod 644 {} \; 2>/dev/null || true
  echo "  -> Credentials restored and secured."
else
  echo "  -> No secure data archive found. Skipping."
fi

echo "[5/8] Install pkgs from pacman..."
PKG_LIST_DIR="$BACKUP_ROOT/pkg-lists"
if [ -f "$PKG_LIST_DIR/pkglist-pacman.txt" ]; then
  pacman -S --needed --noconfirm - <"$PKG_LIST_DIR/pkglist-pacman.txt"
else
  echo "  -> Error: pkglist-pacman.txt not found."
fi

echo "[6/8] Deploy AUR helper (yay)..."
su - "$TARGET_USER" <<'EOF'
set -e

export http_proxy="http://127.0.0.1:7890"
export https_proxy="http://127.0.0.1:7890"
export all_proxy="socks5://127.0.0.1:7890"

if ! command -v yay &>/dev/null; then
  echo "  -> Installing yay via proxy..."
  rm -rf /tmp/yay  
  
  git clone https://aur.archlinux.org/yay.git /tmp/yay
  cd /tmp/yay
  makepkg -si --noconfirm
  rm -rf /tmp/yay
else
  echo "  -> yay is already installed."
fi
EOF

echo "[7/8] Install pkgs from AUR..."
if [ -f "$PKG_LIST_DIR/pkglist-aur.txt" ]; then
  # Execute yay in user context
  su - "$TARGET_USER" -c "yay -S --needed --noconfirm - < \"$PKG_LIST_DIR/pkglist-aur.txt\""
else
  echo "  -> Error: pkglist-aur.txt not found."
fi

echo "[8/8] Clone and stow dotfiles..."
su - "$TARGET_USER" <<EOF
set -e
if [ ! -d "$TARGET_HOME/dot_files" ]; then
  echo "  -> Cloning dot_files repository..."
  # Uses SSH cloning since credentials were restored in step 4
  git clone "$DOTFILES_REPO" "$TARGET_HOME/dot_files"
else
  echo "  -> dot_files already exists. Skipping clone."
fi

echo "  -> Executing stow configuration..."
cd "$TARGET_HOME/dot_files" || exit
for target_dir in */; do
  dir_name="\${target_dir%/}"
  [[ "\$dir_name" == ".git" ]] && continue
  stow -t "$TARGET_HOME" "\$dir_name"
done
EOF

echo "=== Restore Accomplished ==="
echo "Action Required: Please execute 'wsl --shutdown' in Windows PowerShell."
echo "Upon next launch, you will automatically enter the environment as user '$TARGET_USER'."
