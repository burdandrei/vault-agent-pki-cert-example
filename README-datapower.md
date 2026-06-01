# Vault Agent with IBM DataPower Certificate Auto-Update

This configuration extends the basic Vault Agent PKI example to automatically update certificates on IBM DataPower appliances.

## Prerequisites

- IBM DataPower appliance accessible via REST API
- DataPower credentials (default: admin/admin)
- DataPower REST Management Interface enabled on port 5554
- Network connectivity from Vault Agent to DataPower

## Configuration

The [`vault-agent-datapower.hcl`](vault-agent-datapower.hcl) file is configured to:

1. Request certificates from Vault PKI (via the template)
2. Write certificate files locally to the `certs/` directory
3. Automatically upload certificates to DataPower using REST API

## Setup Instructions

### 1. Configure DataPower Connection

Edit [`vault-agent-datapower.hcl`](vault-agent-datapower.hcl) and update the command section:

```hcl
command = "bash -c 'curl -k -u admin:admin -X PUT https://YOUR-DATAPOWER-HOST:5554/mgmt/filestore/default/cert/cert.pem -T certs/cert.pem && curl -k -u admin:admin -X PUT https://YOUR-DATAPOWER-HOST:5554/mgmt/filestore/default/cert/cert.key -T certs/cert.key && curl -k -u admin:admin -X PUT https://YOUR-DATAPOWER-HOST:5554/mgmt/filestore/default/cert/ca.pem -T certs/ca.pem && echo \"Certificate updated on DataPower successfully!\"'"
```

Replace:
- `YOUR-DATAPOWER-HOST` - DataPower hostname or IP
- `admin:admin` - DataPower username:password
- `default` - DataPower domain (change if using different domain)
- `cert/` - Target directory in DataPower filestore

### 2. Follow Basic Vault Setup

Complete steps 1-6 from the main [README.md](README.md):

```bash
# Start Vault dev server
vault server -dev -dev-root-token-id=root -log-level=DEBUG

# Enable audit logging
vault audit enable file file_path=stdout log_raw=true

# Enable PKI
vault secrets enable pki

# Generate root CA
vault write pki/root/generate/internal \
    common_name=example.ie \
    ttl=8760h

# Create role
vault write pki/roles/hc-example-ie \
    allowed_domains=hc.example.ie \
    allow_subdomains=true \
    max_ttl=72h
```

### 3. Run Vault Agent with DataPower Integration

```bash
vault agent -log-level debug -config=./vault-agent-datapower.hcl
```

## How It Works

1. **Certificate Request**: Vault Agent processes [`source.vtmpl`](source.vtmpl) template
2. **Local Storage**: Certificates are written to `certs/` directory
3. **DataPower Upload**: The `command` executes after template rendering:
   - Uploads `cert.pem` (certificate) to DataPower filestore
   - Uploads `cert.key` (private key) to DataPower filestore
   - Uploads `ca.pem` (CA certificate) to DataPower filestore
4. **Auto-Renewal**: Vault Agent monitors certificate TTL and repeats the process before expiration

## DataPower REST API Endpoints Used

- `PUT /mgmt/filestore/{domain}/{directory}/{filename}` - Upload file to filestore

## Security Considerations

1. **Credentials**: Store DataPower credentials securely (consider using environment variables or Vault secrets)
2. **TLS Verification**: The `-k` flag disables certificate verification. For production, use proper TLS certificates
3. **Network Security**: Ensure secure network path between Vault Agent and DataPower
4. **File Permissions**: Certificate files are created with restrictive permissions (0600 for keys)

## Troubleshooting

### Check DataPower Filestore
```bash
curl -k -u admin:admin https://datapower-host:5554/mgmt/filestore/default/cert/
```

### Verify Certificate Upload
```bash
curl -k -u admin:admin https://datapower-host:5554/mgmt/filestore/default/cert/cert.pem
```

### View Vault Agent Logs
The agent runs with `debug` logging to help troubleshoot certificate requests and command execution.

## Advanced Configuration

### Using Environment Variables for Credentials

Modify the command to use environment variables:

```hcl
command = "bash -c 'curl -k -u $DP_USER:$DP_PASS -X PUT https://$DP_HOST:5554/mgmt/filestore/default/cert/cert.pem -T certs/cert.pem && curl -k -u $DP_USER:$DP_PASS -X PUT https://$DP_HOST:5554/mgmt/filestore/default/cert/cert.key -T certs/cert.key && curl -k -u $DP_USER:$DP_PASS -X PUT https://$DP_HOST:5554/mgmt/filestore/default/cert/ca.pem -T certs/ca.pem && echo \"Certificate updated on DataPower successfully!\"'"
```

Then export variables before running:
```bash
export DP_HOST=datapower-host
export DP_USER=admin
export DP_PASS=admin
vault agent -log-level debug -config=./vault-agent-datapower.hcl
```

### Configuring DataPower to Use the Certificates

After certificates are uploaded, configure DataPower objects (Crypto Certificate, Crypto Key, Crypto Identification Credentials) via:
- WebGUI
- CLI
- REST API configuration endpoints

Example REST API call to create/update crypto objects would require additional DataPower-specific configuration.