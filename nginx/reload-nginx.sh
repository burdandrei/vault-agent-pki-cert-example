#!/usr/bin/env bash
# reload-nginx.sh — run by Vault Agent exec after each certificate renewal.
# Sends SIGHUP to the nginx master process inside the running container so it
# reloads the certificate without dropping existing connections.
set -euo pipefail

podman exec nginx-vault nginx -s reload
echo "nginx reloaded at $(date)"
