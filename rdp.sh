#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
. ./.env

rdp=$(command -v xfreerdp3 || command -v xfreerdp || true)
[[ -n $rdp ]] || { echo "Chưa có FreeRDP, cài bằng: sudo apt install freerdp3-x11" >&2; exit 1; }

drives=()
for d in DOCUMENTS DOWNLOAD DESKTOP; do
  p=$(xdg-user-dir "$d" 2>/dev/null || true)
  [[ -d $p && $p != "$HOME" ]] && drives+=("/drive:$(basename "$p"),$p")
done

exec "$rdp" /v:127.0.0.1:3389 /u:"$WIN_USER" /p:"$WIN_PASS" /cert:ignore \
  /t:"Windows 10 - Office" /size:90% +dynamic-resolution \
  /clipboard +auto-reconnect /network:auto /gfx \
  "${drives[@]}" "$@"
