#!/usr/bin/env bash
set -euo pipefail

if [[ -f "/etc/os-release" ]]; then
  # shellcheck disable=SC1091
  source /etc/os-release || true
  echo "[DOCKER] OS: ${PRETTY_NAME:-unknown}"
fi

mkdir -p /work/dist

exec "$@"
