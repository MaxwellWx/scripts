#!/bin/bash
# Shared helpers. Source this file from backup.sh or restore.sh.
# Shell options, traps, and workflow execution belong to the entry scripts.

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

warn() {
  printf 'Warning: %s\n' "$*" >&2
}

require_commands() {
  local cmd
  for cmd in "$@"; do
    command -v "$cmd" >/dev/null 2>&1 ||
      die "Required command not found: $cmd"
  done
}

as_target() {
  runuser -u "$TARGET_USER" -- \
    env \
    -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY \
    HOME="$TARGET_HOME" \
    USER="$TARGET_USER" \
    LOGNAME="$TARGET_USER" \
    http_proxy="$PROXY_URL" \
    https_proxy="$PROXY_URL" \
    all_proxy="$SOCKS_URL" \
    "$@"
}

# Print an empty string when WSL interop is unavailable.
resolve_windows_home() {
  local profile windows_home

  if ! command -v cmd.exe >/dev/null 2>&1 ||
    ! command -v wslpath >/dev/null 2>&1; then
    return 0
  fi

  if ! profile=$(cmd.exe /c "echo %USERPROFILE%" 2>/dev/null); then
    return 0
  fi

  profile=${profile//$'\r'/}
  [[ -n "$profile" ]] || return 0

  if windows_home=$(wslpath "$profile"); then
    printf '%s\n' "$windows_home"
  fi

  return 0
}

publish_snapshot() (
  set -Eeuo pipefail
  umask 077

  local snapshot
  local work_dir

  require_commands realpath tar sha256sum mktemp gzip

  snapshot=$(realpath -- "$1")

  [[ -f "$snapshot/COMPLETE" ]] ||
    die "Snapshot is incomplete"

  [[ -s "$snapshot/SHA256SUMS" ]] ||
    die "Snapshot checksum manifest is missing"

  (
    cd -- "$snapshot"
    sha256sum --check --strict SHA256SUMS
  )

  mkdir -p -- "$PUBLISHED_DIR"

  work_dir=$(mktemp -d "$PUBLISHED_DIR/.publish.XXXXXXXX")
  trap 'rm -rf -- "$work_dir"' EXIT

  echo "Preparing publication without outer encryption..."

  tar -czf "$work_dir/latest.tar.gz" \
    -C "$snapshot" .

  # Read the complete archive to detect compression errors.
  gzip -t "$work_dir/latest.tar.gz"

  (
    cd -- "$work_dir"
    sha256sum latest.tar.gz >SHA256SUMS
    sha256sum --check --strict SHA256SUMS
  )

  mv -f -- \
    "$work_dir/latest.tar.gz" \
    "$PUBLISHED_DIR/latest.tar.gz"

  mv -f -- \
    "$work_dir/SHA256SUMS" \
    "$PUBLISHED_DIR/SHA256SUMS"

  printf 'Publication prepared: %s\n' "$PUBLISHED_DIR/latest.tar.gz"
)
