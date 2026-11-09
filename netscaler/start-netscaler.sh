#!/usr/bin/env bash
# start-netscaler.sh — run the Citrix NetScaler CPX container.
#
# NetScaler CPX is a containerised ADC that exposes the same NITRO REST
# Management API as hardware/VPX/MPX appliances.  Bootstrap TLS certificates
# (7-day TTL, signed by terraform.hashicorp.ibm) are written to certs/ by
# `terraform apply` so the container can start immediately without a prior
# Vault Agent run.
#
# Exposed endpoints:
#   HTTP  redirect   → http://localhost:9080
#   HTTPS TLS        → https://localhost:9443
#   NITRO REST API   → http://localhost:32080/nitro/v1/
#
# Must be run from the repo root:
#   bash netscaler/start-netscaler.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

podman rm -f netscaler-vault 2>/dev/null || true

# NetScaler CPX — containerised ADC, pulled from quay.io/netscaler/netscaler-cpx.
# Override the tag with NETSCALER_IMAGE if needed.
# The /nsconfig/ssl volume is where CPX reads cert and key files referenced by
# NITRO sslcertkey objects.
IMAGE="${NETSCALER_IMAGE:-quay.io/netscaler/netscaler-cpx:14.1-73.30}"

docker run -d \
  --name netscaler-vault \
  --privileged \
  -e EULA=yes \
  -p 9080:9080 \
  -p 9443:9443 \
  -p 32080:32080 \
  -v "${REPO_ROOT}/certs:/nsconfig/ssl:ro" \
  "${IMAGE}"

echo "NetScaler CPX container started"
echo "  HTTP  redirect   → http://localhost:9080"
echo "  HTTPS TLS        → https://localhost:9443"
echo "  NITRO REST API   → http://localhost:32080/nitro/v1/"
echo "  Credentials: nsroot / nsroot"
echo ""
echo "  CPX SSL certkey object name: vault-demo"
echo "  CPX cert file:               netscaler-cert.pem  (in /nsconfig/ssl)"
echo "  CPX key  file:               netscaler-privkey.pem (in /nsconfig/ssl)"
