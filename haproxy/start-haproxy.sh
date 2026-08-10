#!/usr/bin/env bash
# start-haproxy.sh — run the HAProxy container.
#
# Mounts:
#   haproxy/haproxy.cfg → /usr/local/etc/haproxy/haproxy.cfg  (read-only)
#   certs/              → /certs                               (read-only)
#
# Must be run from the repo root:
#   bash haproxy/start-haproxy.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

podman rm -f haproxy-vault 2>/dev/null || true

podman run -d \
  --name haproxy-vault \
  -p 8090:8080 \
  -p 8453:8443 \
  -v "${REPO_ROOT}/haproxy/haproxy.cfg:/usr/local/etc/haproxy/haproxy.cfg:ro" \
  -v "${REPO_ROOT}/haproxy/success.html:/etc/haproxy/success.html:ro" \
  -v "${REPO_ROOT}/certs:/certs:ro" \
  haproxy:alpine

echo "HAProxy container started"
echo "  HTTP  → http://localhost:8090"
echo "  HTTPS → https://localhost:8453"
