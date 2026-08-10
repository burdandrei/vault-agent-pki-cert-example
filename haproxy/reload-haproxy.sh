#!/usr/bin/env bash
# reload-haproxy.sh — run by Vault Agent exec after each certificate renewal.
#
# Steps:
#   1. Assemble the HAProxy bundle: privkey + cert + CA chain in one PEM file.
#      HAProxy requires key first, then cert, then any intermediate chain.
#   2. Signal the running HAProxy container to reload its config and certs.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CERT_PEM="${REPO_ROOT}/certs/haproxy-cert.pem"
KEY_PEM="${REPO_ROOT}/certs/haproxy-privkey.pem"
BUNDLE="${REPO_ROOT}/certs/haproxy-bundle.pem"

# ---------------------------------------------------------------------------
# 1. Assemble bundle: key must come before the certificate in HAProxy's crt file
# ---------------------------------------------------------------------------
echo "Assembling HAProxy bundle..."
cat "${KEY_PEM}" "${CERT_PEM}" > "${BUNDLE}"
chmod 0600 "${BUNDLE}"

# ---------------------------------------------------------------------------
# 2. Signal HAProxy inside the container to reload
#    HAProxy reloads certs on SIGUSR2 (soft-stop + new master) in master-worker
#    mode, or on a simple kill -HUP to the master PID.  The simplest portable
#    approach is to send a reload via the container runtime.
# ---------------------------------------------------------------------------
podman kill --signal=HUP haproxy-vault
echo "HAProxy reloaded at $(date)"
