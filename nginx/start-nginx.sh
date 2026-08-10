#!/usr/bin/env bash
# start-nginx.sh — run the nginx container.
#
# Mounts:
#   nginx/nginx.conf  → /etc/nginx/nginx.conf  (read-only)
#   certs/            → /certs                 (read-only)
#
# Must be run from the repo root:
#   bash nginx/start-nginx.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

podman rm -f nginx-vault 2>/dev/null || true

podman run -d \
  --name nginx-vault \
  -p 8080:80 \
  -p 8443:443 \
  -v "${REPO_ROOT}/nginx/nginx.conf:/etc/nginx/nginx.conf:ro" \
  -v "${REPO_ROOT}/nginx/success.html:/usr/share/nginx/html/index.html:ro" \
  -v "${REPO_ROOT}/certs:/certs:ro" \
  nginx:alpine

echo "nginx container started"
echo "  HTTP  → http://localhost:8080"
echo "  HTTPS → https://localhost:8443"
