#!/bin/bash

set -e            # exit immediately if a command fails
set -u            # error on undefined variables
#set -x            # debug mode (prints commands)
set -o pipefail   # fail if any command in a pipeline fails

# Set default credentials and host if not provided via environment variables
DATAPOWER_USER="${DATAPOWER_USER:-admin}"
DATAPOWER_PASSWORD="${DATAPOWER_PASSWORD:-admin}"
DATAPOWER_HOST="${DATAPOWER_HOST:-localhost}"
DATAPOWER_PORT="${DATAPOWER_PORT:-5554}"

BASE_URL="https://${DATAPOWER_HOST}:${DATAPOWER_PORT}"

# ---------------------------------------------------------------------------
# upload_file <local_path> <dest_filename>
# Writes a file into the DataPower cert:/// filestore.
# ---------------------------------------------------------------------------
upload_file() {
    local file_path=$1
    local dest_name=$2

    local file_content
    file_content=$(base64 < "${file_path}")

    local json_payload
    json_payload=$(cat <<EOF
{
  "file": {
    "name": "${dest_name}",
    "content": "${file_content}"
  }
}
EOF
)

    curl -k -u "${DATAPOWER_USER}:${DATAPOWER_PASSWORD}" \
        -X PUT \
        -H "Content-Type: application/json" \
        "${BASE_URL}/mgmt/filestore/default/cert/${dest_name}" \
        -d "${json_payload}"

    echo ""
}

# ---------------------------------------------------------------------------
# reload_cert <name> <filename>
# PUT the CryptoCertificate config object back to itself.
# This causes DataPower to re-read the backing file from cert:///.
# ---------------------------------------------------------------------------
reload_cert() {
    local name=$1
    local filename=$2

    curl -k -u "${DATAPOWER_USER}:${DATAPOWER_PASSWORD}" \
        -X PUT \
        -H "Content-Type: application/json" \
        "${BASE_URL}/mgmt/config/default/CryptoCertificate/${name}" \
        -d "{\"CryptoCertificate\":{\"name\":\"${name}\",\"mAdminState\":\"enabled\",\"Filename\":\"${filename}\",\"IgnoreExpiration\":\"off\"}}"

    echo ""
}

# ---------------------------------------------------------------------------
# reload_key <name> <filename>
# PUT the CryptoKey config object back to itself.
# ---------------------------------------------------------------------------
reload_key() {
    local name=$1
    local filename=$2

    curl -k -u "${DATAPOWER_USER}:${DATAPOWER_PASSWORD}" \
        -X PUT \
        -H "Content-Type: application/json" \
        "${BASE_URL}/mgmt/config/default/CryptoKey/${name}" \
        -d "{\"CryptoKey\":{\"name\":\"${name}\",\"mAdminState\":\"enabled\",\"Filename\":\"${filename}\"}}"

    echo ""
}

# ---------------------------------------------------------------------------
# save_config
# Persists the running config so the reloaded objects survive a restart.
# ---------------------------------------------------------------------------
save_config() {
    curl -k -u "${DATAPOWER_USER}:${DATAPOWER_PASSWORD}" \
        -X POST \
        -H "Content-Type: application/json" \
        "${BASE_URL}/mgmt/actionqueue/default" \
        -d '{"SaveConfig":{}}'

    echo ""
}

# ---------------------------------------------------------------------------
# Upload renewed certificate files
# ---------------------------------------------------------------------------
echo "Uploading demo-sscert.pem..."
upload_file "datapower/certs/demo-sscert.pem" "demo-sscert.pem"

echo "Uploading demo-privkey.pem..."
upload_file "datapower/certs/demo-privkey.pem" "demo-privkey.pem"

# ---------------------------------------------------------------------------
# Re-apply the crypto config objects so DataPower re-reads the new files.
# Without this the running TLS context keeps the old certificate material.
# ---------------------------------------------------------------------------
echo "Reloading CryptoCertificate 'demo'..."
reload_cert "demo" "cert:///demo-sscert.pem"

echo "Reloading CryptoKey 'demo'..."
reload_key "demo" "cert:///demo-privkey.pem"

echo "Saving config..."
save_config

echo "Certificate rotated and reloaded on DataPower successfully!"
