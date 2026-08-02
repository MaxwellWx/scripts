#!/usr/bin/env bash

set -euo pipefail

# ------------------------------------------------------------
# 修改成你实际的 SumatraPDF.exe
# ------------------------------------------------------------

SUMATRA_WIN='C:\Program Files\SumatraPDF\SumatraPDF.exe'

SUMATRA="$(wslpath -u "$SUMATRA_WIN")"

if [[ ! -x "$SUMATRA" ]]; then
    echo "SumatraPDF not found:"
    echo "$SUMATRA"
    exit 1
fi

# ------------------------------------------------------------
# VimTeX 传进来的 Linux 路径转换成 Windows 路径
# ------------------------------------------------------------

args=()

for arg in "$@"; do
    if [[ "$arg" == /* || "$arg" == ./* || "$arg" == ../* || -e "$arg" ]]; then
        args+=("$(wslpath -w "$arg")")
    else
        args+=("$arg")
    fi
done

"$SUMATRA" "${args[@]}" >/dev/null 2>&1 &
