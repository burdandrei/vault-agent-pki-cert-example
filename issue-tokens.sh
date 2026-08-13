#!/usr/bin/env bash
# issue-tokens.sh
#
# Mints one Vault service token per issuer role (datapower, nginx, haproxy)
# and writes each token to its own file so the corresponding Vault Agent
# config can authenticate with the least-privilege token.
#
# Token files written:
#   .vault-token-datapower   <- consumed by datapower.hcl / datapower-init.hcl
#   .vault-token-nginx       <- consumed by nginx.hcl
#   .vault-token-haproxy     <- consumed by haproxy.hcl / haproxy-init.hcl
#
# Usage:
#   bash ./issue-tokens.sh
#
# Environment variables (all optional — defaults target a local dev server):
#   VAULT_ADDR   Vault address            (default: http://127.0.0.1:8200)
#   VAULT_TOKEN  Token with permissions to call vault token create
#                (default: root — fine for local dev)
#   TOKEN_TTL    Initial TTL for each issued token (default: 1h)

set -euo pipefail

VAULT_ADDR="${VAULT_ADDR:-http://127.0.0.1:8200}"
VAULT_TOKEN="${VAULT_TOKEN:-root}"
TOKEN_TTL="${TOKEN_TTL:-1h}"

export VAULT_ADDR VAULT_TOKEN

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

log()  { printf '[issue-tokens] %s\n' "$*"; }
die()  { printf '[issue-tokens] ERROR: %s\n' "$*" >&2; exit 1; }

mint_token() {
  local role="$1"
  local policy="$2"
  local out_file="$3"

  log "Minting token  role=${role}  policy=${policy}  -> ${out_file}"

  local token
  token=$(vault token create \
    -role="$role" \
    -policy="$policy" \
    -ttl="$TOKEN_TTL" \
    -display-name="${role}-agent" \
    -orphan \
    -renewable \
    -format=json \
    | python3 -c "import sys,json; print(json.load(sys.stdin)['auth']['client_token'])")

  printf '%s' "$token" > "$out_file"
  chmod 600 "$out_file"
  log "  written -> ${out_file}"
}

# ---------------------------------------------------------------------------
# Verify Vault is reachable before attempting anything
# ---------------------------------------------------------------------------

vault status > /dev/null 2>&1 || die "Vault at $VAULT_ADDR is sealed or unreachable"

# ---------------------------------------------------------------------------
# Issue one token per service
# ---------------------------------------------------------------------------

mint_token "datapower" "datapower-pki" ".vault-token-datapower"
mint_token "nginx"     "nginx-pki"     ".vault-token-nginx"
mint_token "haproxy"   "haproxy-pki"   ".vault-token-haproxy"

log "Done."
