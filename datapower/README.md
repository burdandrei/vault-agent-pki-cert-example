# Vault Agent with IBM DataPower Certificate Auto-Update

This example shows how to use Vault Agent to generate initial certificates for IBM DataPower, start a local DataPower container with those certificates mounted, and then keep selected certificates updated from Vault by uploading refreshed files through the DataPower REST Management API.

## Overview

The flow in this directory is:

1. Start Vault and configure PKI.
2. Generate the initial certificate set before starting DataPower with [`vault agent -log-level debug -config=./vault-agent-init.hcl -exit-after-auth`](datapower/vault-agent-init.hcl:1).
3. Start DataPower with [`start-datapower.sh`](datapower/start-datapower.sh).
4. Run Vault Agent continuously with [`vault-agent-datapower.hcl`](datapower/vault-agent-datapower.hcl) to renew and upload the demo certificate to DataPower.

## Prerequisites

- Vault CLI installed
- IBM DataPower container image access
- Docker available locally
- Network access to the local Vault server from this environment
- `curl` and `base64` available
- A valid Vault token stored in [`../.vault-token`](.vault-token)

## Directory Structure

```text
datapower/
├── README.md
├── start-datapower.sh
├── upload-certs-to-datapower.sh
├── vault-agent-init.hcl
├── vault-agent-datapower.hcl
├── templates/
│   ├── webgui.vtmpl
│   ├── dp-ui.vtmpl
│   └── demo.vtmpl
├── certs/
├── config/
└── local/
```

## Files

- [`vault-agent-init.hcl`](datapower/vault-agent-init.hcl) renders the initial certificate files once and exits.
- [`vault-agent-datapower.hcl`](datapower/vault-agent-datapower.hcl) continuously renders the demo certificate and runs [`upload-certs-to-datapower.sh`](datapower/upload-certs-to-datapower.sh) after updates.
- [`start-datapower.sh`](datapower/start-datapower.sh) starts the local DataPower container and mounts local config, local storage, and generated certs.
- [`upload-certs-to-datapower.sh`](datapower/upload-certs-to-datapower.sh) uploads generated certificate files into the DataPower filestore over REST API.
- [`templates/webgui.vtmpl`](datapower/templates/webgui.vtmpl), [`templates/dp-ui.vtmpl`](datapower/templates/dp-ui.vtmpl), and [`templates/demo.vtmpl`](datapower/templates/demo.vtmpl) define the Vault PKI template rendering behavior.

## Vault Setup

From the repository root, start Vault in dev mode:

```bash
vault server -dev -dev-root-token-id=root -log-level=DEBUG
```

Enable audit logging:

```bash
vault audit enable file file_path=stdout log_raw=true
```

Enable PKI:

```bash
vault secrets enable pki
```

Generate a root CA:

```bash
vault write pki/root/generate/internal \
  common_name=vault.hashicorp.ibm \
  ttl=8760h
```

Create a role:

```bash
vault write pki/roles/datapower \
  allowed_domains=datapower.hashicorp.ibm \
  allow_subdomains=true \
  max_ttl=72h
```

## Generate Initial Certificates Before Starting DataPower

Change into [`datapower/`](datapower/) and render the initial certificates once:

```bash
cd ./datapower
vault agent -log-level debug -config=./vault-agent-init.hcl -exit-after-auth
```

This uses [`vault-agent-init.hcl`](datapower/vault-agent-init.hcl), which renders:

- [`templates/webgui.vtmpl`](datapower/templates/webgui.vtmpl) to `certs/webgui.out`
- [`templates/dp-ui.vtmpl`](datapower/templates/dp-ui.vtmpl) to `certs/dp-ui.out`
- [`templates/demo.vtmpl`](datapower/templates/demo.vtmpl) to `certs/demo.out`

Use this step before starting DataPower so the initial certificate material already exists on disk.

## Start DataPower

After the initial certificates are generated, start DataPower:

```bash
cd ./datapower
bash ./start-datapower.sh
```

[`start-datapower.sh`](datapower/start-datapower.sh) starts a local container and mounts:

- [`datapower/config/`](datapower/config/)
- [`datapower/local/`](datapower/local/)
- [`datapower/certs/`](datapower/certs/)

Exposed endpoints from the script:

- Web UI: `https://localhost:9090`
- SOMA API: `https://localhost:5550`
- REST Management API: `https://localhost:5554`
- Demo TLS service: `https://localhost:8043`

Default credentials printed by the script are `admin/admin`.

## Run Continuous Vault Agent Updates

To keep the demo certificate refreshed and uploaded into DataPower, run:

```bash
cd ./datapower
vault agent -log-level debug -config=./vault-agent-datapower.hcl
```

[`vault-agent-datapower.hcl`](datapower/vault-agent-datapower.hcl) currently:

- authenticates with `token_file`
- reads the token from [`../.vault-token`](.vault-token)
- renders [`templates/demo.vtmpl`](datapower/templates/demo.vtmpl)
- writes to `certs/demo.out`
- executes [`upload-certs-to-datapower.sh`](datapower/upload-certs-to-datapower.sh)

## Authentication Options

[`vault-agent-datapower.hcl`](datapower/vault-agent-datapower.hcl) keeps `token_file` active by default and includes commented examples for other auth methods.

### Token File

Active by default:

```hcl
method {
   type = "token_file"

  config = {
    token_file_path = "../.vault-token"
  }
}
```

### Kubernetes Auth

[`vault-agent-datapower.hcl`](datapower/vault-agent-datapower.hcl) includes a commented example for Kubernetes auth. Uncomment it and disable the token block if needed:

```hcl
# method {
#   type = "kubernetes"
#
#   mount_path = "auth/kubernetes"
#
#   config = {
#     role = "datapower-role"
#   }
# }
```

### AWS Auth

[`vault-agent-datapower.hcl`](datapower/vault-agent-datapower.hcl) also includes a commented example for AWS auth:

```hcl
# method {
#   type = "aws"
#
#   mount_path = "auth/aws"
#
#   config = {
#     type = "iam"
#     role = "datapower-role"
#   }
# }
```

## DataPower Upload Behavior

[`upload-certs-to-datapower.sh`](datapower/upload-certs-to-datapower.sh) uploads files to the DataPower filestore using:

- `PUT /mgmt/filestore/default/cert/{filename}`
- `Content-Type: application/json`
- basic authentication with environment-configurable credentials

Default environment values in the script:

- `DATAPOWER_HOST=localhost`
- `DATAPOWER_PORT=5554`
- `DATAPOWER_USER=admin`
- `DATAPOWER_PASSWORD=admin`

The script currently uploads:

- `certs/demo-sscert.pem` as `demo-sscert.pem`
- `certs/demo-privkey.key` as `demo-privkey.pem`

## Useful Commands

Check a certificate:

```bash
openssl x509 -in ./certs/demo-sscert.pem -text -noout
```

Check certificate dates:

```bash
openssl x509 -in ./certs/demo-sscert.pem -noout -dates
```

Test the DataPower filestore endpoint:

```bash
curl -k -u admin:admin \
  https://localhost:5554/mgmt/filestore/default/cert/
```

## Troubleshooting

### Vault Agent exits immediately

If you used [`-exit-after-auth`](datapower/vault-agent-init.hcl:1), that is expected for the initial one-shot render flow.

### No certificates generated

Verify:

- Vault dev server is running on `http://127.0.0.1:8200`
- PKI is enabled and configured
- [`../.vault-token`](.vault-token) exists relative to [`datapower/vault-agent-init.hcl`](datapower/vault-agent-init.hcl)
- the templates in [`datapower/templates/`](datapower/templates/) reference valid Vault PKI paths

### Upload to DataPower fails

Verify:

- DataPower is running
- REST Management API is reachable on `https://localhost:5554`
- credentials match the running container
- the filenames expected by [`upload-certs-to-datapower.sh`](datapower/upload-certs-to-datapower.sh) exist in [`datapower/certs/`](datapower/certs/)

### TLS warnings from curl

[`upload-certs-to-datapower.sh`](datapower/upload-certs-to-datapower.sh) uses `curl -k`, which disables certificate verification for local testing.

## Summary

Recommended sequence:

1. Start Vault and configure PKI.
2. Run [`vault agent -log-level debug -config=./vault-agent-init.hcl -exit-after-auth`](datapower/vault-agent-init.hcl:1) from [`datapower/`](datapower/).
3. Start DataPower with [`start-datapower.sh`](datapower/start-datapower.sh).
4. Run [`vault agent -log-level debug -config=./vault-agent-datapower.hcl`](datapower/vault-agent-datapower.hcl:1) for ongoing updates.