#!/bin/bash

set -Eeuo pipefail
umask 077

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/common.sh"

[[ $# -eq 1 ]] ||
  die "Usage: $0 SNAPSHOT_DIRECTORY"

require_commands realpath tar gpg sha256sum mktemp flock

SNAPSHOT=$(realpath -- "$1")

[[ -f "$SNAPSHOT/COMPLETE" ]] ||
  die "Snapshot is incomplete"

[[ -s "$SNAPSHOT/SHA256SUMS" ]] ||
  die "Missing checksum manifest"

(
  cd -- "$SNAPSHOT"
  sha256sum --check SHA256SUMS
) || die "Snapshot verification failed"

exec 9>"$SCRIPT_DIR/.backup.lock"
flock -n 9 || die "Another backup or publication is running"

WORK_DIR=$(mktemp -d "$SCRIPT_DIR/.publish.XXXXXXXX")
trap 'rm -rf -- "$WORK_DIR"' EXIT

printf 'Encrypting the complete snapshot for publication...\n'

tar -czf - -C "$SNAPSHOT" . |
  gpg \
    --pinentry-mode loopback \
    --symmetric \
    --cipher-algo AES256 \
    --output "$WORK_DIR/latest.tar.gz.gpg"

(
  cd -- "$WORK_DIR"
  sha256sum latest.tar.gz.gpg >SHA256SUMS
)

mkdir -p -- "$SCRIPT_DIR/published"

mv -f -- \
  "$WORK_DIR/latest.tar.gz.gpg" \
  "$SCRIPT_DIR/published/latest.tar.gz.gpg"

mv -f -- \
  "$WORK_DIR/SHA256SUMS" \
  "$SCRIPT_DIR/published/SHA256SUMS"

printf 'Publication files prepared in %s\n' "$SCRIPT_DIR/published"
printf 'Review, commit, and push them with Git.\n'
