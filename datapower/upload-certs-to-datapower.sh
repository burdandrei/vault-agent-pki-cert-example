#!/bin/bash

set -e   # exit immediately if a command fails
set -u   # error on undefined variables
set -x   # debug mode (prints commands)
set -o pipefail  # fail if any command in a pipeline fails

# Set default credentials and host if not provided via environment variables
DATAPOWER_USER="${DATAPOWER_USER:-admin}"
DATAPOWER_PASSWORD="${DATAPOWER_PASSWORD:-admin}"
DATAPOWER_HOST="${DATAPOWER_HOST:-localhost}"
DATAPOWER_PORT="${DATAPOWER_PORT:-5554}"

# Function to upload file to DataPower filestore
upload_file() {
    local file_path=$1
    local dest_name=$2
    
    # Read file content and base64 encode it
    local file_content=$(base64 < "${file_path}")
    
    # Create JSON payload
    local json_payload=$(cat <<EOF
{
  "file": {
    "name": "${dest_name}",
    "content": "${file_content}"
  }
}
EOF
)
    
    # Upload to DataPower
    curl -k -u "${DATAPOWER_USER}:${DATAPOWER_PASSWORD}" \
        -X PUT \
        -H "Content-Type: application/json" \
        "https://${DATAPOWER_HOST}:${DATAPOWER_PORT}/mgmt/filestore/default/cert/${dest_name}" \
        -d "${json_payload}"
    
    echo ""
}

# Upload certificates to DataPower
echo "Uploading cert.pem..."
upload_file "certs/demo-sscert.pem" "demo-sscert.pem"

echo "Uploading cert.key..."
upload_file "certs/demo-privkey.key" "demo-privkey.pem"


echo "Certificate updated on DataPower successfully!"

# Made with Bob
