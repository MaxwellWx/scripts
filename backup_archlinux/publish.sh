#!/bin/bash

set -Eeuo pipefail
umask 077

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/common.sh"
source "$SCRIPT_DIR/config.sh"

[[ $# -eq 1 ]] ||
  die "Usage: $0 SNAPSHOT_DIRECTORY"

require_commands flock

exec 9>"$LOCK_FILE"
flock -n 9 || die "Another backup or publication is running"

publish_snapshot "$1"

echo "Publication completed."
echo "Git commit and push are still required."
