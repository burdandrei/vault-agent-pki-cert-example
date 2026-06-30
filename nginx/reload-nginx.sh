#!/usr/bin/env bash
# reload-nginx.sh — sent after Vault Agent writes a renewed certificate.
# Sends SIGHUP to the running nginx master process so it reloads without
# dropping existing connections.
set -euo pipefail

nginx -s reload
echo "nginx reloaded at $(date)"
