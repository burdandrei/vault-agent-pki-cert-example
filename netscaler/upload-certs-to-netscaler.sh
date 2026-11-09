#!/bin/bash
# upload-certs-to-netscaler.sh — called by Vault Agent exec after every renewal.
#
# What this script does (mirrors DataPower's upload-certs-to-datapower.sh):
#
#   1. Uploads the renewed cert and key files to the NetScaler filesystem via
#      the NITRO systemfile API (POST/PUT to /nitro/v1/config/systemfile).
#      Target location inside the appliance: /nsconfig/ssl/
#
#   2. Updates the SSL certkey object ("vault-demo") to point to the new
#      files.  On NetScaler, updating the certkey object causes the ADC to
#      immediately re-read the cert material from disk and push it to all
#      virtual servers and services that reference that certkey — no rebind
#      needed.
#
#   3. Saves the running config so the update survives a reboot.
#
# Environment variable overrides (all optional):
#
#   NETSCALER_HOST      default: localhost
#   NETSCALER_PORT      default: 32080   (NITRO HTTP management port for CPX)
#   NETSCALER_USER      default: nsroot
#   NETSCALER_PASSWORD  default: nsroot
#
# Must be run from the repo root (cert paths are relative):
#   bash netscaler/upload-certs-to-netscaler.sh

set -e
set -u
set -o pipefail

NETSCALER_HOST="${NETSCALER_HOST:-localhost}"
NETSCALER_PORT="${NETSCALER_PORT:-32080}"
NETSCALER_USER="${NETSCALER_USER:-nsroot}"
NETSCALER_PASSWORD="${NETSCALER_PASSWORD:-nsroot}"

BASE_URL="http://${NETSCALER_HOST}:${NETSCALER_PORT}/nitro/v1"

# ---------------------------------------------------------------------------
# NITRO requires a session cookie for all API calls.
# We obtain it by POSTing credentials to /config/login.
# ---------------------------------------------------------------------------
login() {
    NITRO_COOKIE=$(curl -sf \
        -X POST \
        -H "Content-Type: application/json" \
        -c /tmp/nitro-cookies.txt \
        "${BASE_URL}/config/login" \
        -d "{\"login\":{\"username\":\"${NETSCALER_USER}\",\"password\":\"${NETSCALER_PASSWORD}\"}}" \
        -w "\n%{http_code}" | tail -1)

    if [ "${NITRO_COOKIE}" != "201" ]; then
        echo "ERROR: NITRO login failed (HTTP ${NITRO_COOKIE})" >&2
        exit 1
    fi
    echo "NITRO login successful."
}

# ---------------------------------------------------------------------------
# logout
# Cleanly invalidate the NITRO session.
# ---------------------------------------------------------------------------
logout() {
    curl -sf \
        -X POST \
        -H "Content-Type: application/json" \
        -b /tmp/nitro-cookies.txt \
        "${BASE_URL}/config/logout" \
        -d '{"logout":{}}' > /dev/null 2>&1 || true
    rm -f /tmp/nitro-cookies.txt
}

# ---------------------------------------------------------------------------
# upload_file <local_path> <dest_filename>
# Writes a file into the NetScaler /nsconfig/ssl/ filestore via NITRO.
# NITRO systemfile API: POST creates, PUT replaces an existing file.
# ---------------------------------------------------------------------------
upload_file() {
    local file_path=$1
    local dest_name=$2

    local file_content
    file_content=$(base64 < "${file_path}")

    local json_payload
    json_payload=$(cat <<EOF
{
  "systemfile": {
    "filename":     "${dest_name}",
    "filecontent":  "${file_content}",
    "filelocation": "/nsconfig/ssl",
    "fileencoding": "BASE64"
  }
}
EOF
)

    # Try PUT (update) first; if the file does not exist yet, fall back to POST
    local http_code
    http_code=$(curl -sf \
        -X PUT \
        -H "Content-Type: application/json" \
        -b /tmp/nitro-cookies.txt \
        "${BASE_URL}/config/systemfile/${dest_name}" \
        -d "${json_payload}" \
        -o /dev/null \
        -w "%{http_code}")

    if [ "${http_code}" = "404" ] || [ "${http_code}" = "000" ]; then
        # File does not exist — create it
        http_code=$(curl -sf \
            -X POST \
            -H "Content-Type: application/json" \
            -b /tmp/nitro-cookies.txt \
            "${BASE_URL}/config/systemfile" \
            -d "${json_payload}" \
            -o /dev/null \
            -w "%{http_code}")
    fi

    echo "  upload ${dest_name}: HTTP ${http_code}"
}

# ---------------------------------------------------------------------------
# update_certkey <certkey_name> <cert_filename> <key_filename>
# Issues a NITRO "update" action on the sslcertkey object.
# NetScaler re-reads the cert and key files from /nsconfig/ssl/ and
# immediately pushes the new material to all bound virtual servers and
# services — no rebind required.
# ---------------------------------------------------------------------------
update_certkey() {
    local name=$1
    local cert_file=$2
    local key_file=$3

    # First try updating an existing certkey object
    local http_code
    http_code=$(curl -sf \
        -X PUT \
        -H "Content-Type: application/json" \
        -b /tmp/nitro-cookies.txt \
        "${BASE_URL}/config/sslcertkey" \
        -d "{\"sslcertkey\":{
              \"certkey\":  \"${name}\",
              \"cert\":     \"/nsconfig/ssl/${cert_file}\",
              \"key\":      \"/nsconfig/ssl/${key_file}\",
              \"inform\":   \"PEM\",
              \"expirymonitor\": \"ENABLED\"
            }}" \
        -o /dev/null \
        -w "%{http_code}")

    if [ "${http_code}" = "404" ] || [ "${http_code}" = "000" ]; then
        # Object does not exist yet — create it
        http_code=$(curl -sf \
            -X POST \
            -H "Content-Type: application/json" \
            -b /tmp/nitro-cookies.txt \
            "${BASE_URL}/config/sslcertkey" \
            -d "{\"sslcertkey\":{
                  \"certkey\":  \"${name}\",
                  \"cert\":     \"/nsconfig/ssl/${cert_file}\",
                  \"key\":      \"/nsconfig/ssl/${key_file}\",
                  \"inform\":   \"PEM\",
                  \"expirymonitor\": \"ENABLED\"
                }}" \
            -o /dev/null \
            -w "%{http_code}")
    fi

    echo "  update sslcertkey '${name}': HTTP ${http_code}"
}

# ---------------------------------------------------------------------------
# save_config
# Persists the running configuration so the updated certkey survives a restart.
# ---------------------------------------------------------------------------
save_config() {
    local http_code
    http_code=$(curl -sf \
        -X POST \
        -H "Content-Type: application/json" \
        -b /tmp/nitro-cookies.txt \
        "${BASE_URL}/config/nsconfig?action=save" \
        -d '{"nsconfig":{}}' \
        -o /dev/null \
        -w "%{http_code}")
    echo "  save config: HTTP ${http_code}"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
echo "=== NetScaler cert rotation at $(date) ==="

login

echo "Uploading netscaler-cert.pem..."
upload_file "certs/netscaler-cert.pem" "netscaler-cert.pem"

echo "Uploading netscaler-privkey.pem..."
upload_file "certs/netscaler-privkey.pem" "netscaler-privkey.pem"

echo "Updating SSL certkey object 'vault-demo'..."
update_certkey "vault-demo" "netscaler-cert.pem" "netscaler-privkey.pem"

echo "Saving running config..."
save_config

logout

echo "Certificate rotated and reloaded on NetScaler successfully!"
