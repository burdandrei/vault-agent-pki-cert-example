# Vault Agent PKI Certificate Example

This repository demonstrates two Vault Agent workflows:

1. **Basic** — Vault Agent requests and renews a PKI certificate from Vault.
2. **DataPower** — Vault Agent generates certificates for IBM DataPower, starts the container, and keeps selected certificates updated via the DataPower REST Management API.

Infrastructure (audit device, PKI engine, root CA, intermediate CA, and roles) is managed with Terraform.

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/downloads) >= 1.3
- [Vault CLI](https://developer.hashicorp.com/vault/downloads)
- IBM DataPower container image access *(DataPower flow only)*
- Docker *(DataPower flow only)*
- `curl` available *(DataPower flow only)*

---

## 1. Start Vault in development mode

```bash
vault server -dev -dev-root-token-id=root -log-level=DEBUG
```

## 2. Export environment variables

```bash
export VAULT_ADDR='http://127.0.0.1:8200'
export VAULT_TOKEN='root'
export VAULT_SKIP_VERIFY='true'
```

## 3. Apply Terraform

The Terraform configuration in `./terraform` provisions:

- File audit device (stdout, raw format)
- Root PKI secrets engine mounted at `pki`
- Root CA (`vault.hashicorp.ibm`, TTL 1 year)
- Intermediate PKI secrets engine mounted at `pki_int` (signed by the root CA)
- PKI role `demoissuer` (allowed domain `demo.vault.hashicorp.ibm`, max TTL 72h) — issues from intermediate
- PKI role `datapower` (allowed domain `datapower.hashicorp.ibm`, max TTL 72h) — issues from intermediate

```bash
cd terraform
terraform init
terraform apply
```

After a successful apply, Terraform prints the outputs:

| Output                 | Description                                    |
| ---------------------- | ---------------------------------------------- |
| `pki_mount_path`       | Mount path of the root PKI engine              |
| `pki_int_mount_path`   | Mount path of the intermediate PKI engine      |
| `root_ca_common_name`  | Common name of the root CA                     |
| `role_name`            | PKI role name for issuing certs                |
| `issue_path`           | Vault path for demoissuer certificate issuance |
| `datapower_issue_path` | Vault path for DataPower certificate issuance  |

---

## Basic Flow — Vault Agent PKI Certificate

### Start Vault Agent

```bash
vault agent -log-level debug -config=./echo.hcl
```

Vault Agent uses `pki_int/issue/demoissuer` to periodically request and renew certificates, writing them to `certs/`.

### Verify the issued certificate

```bash
openssl x509 -in certs/cert.pem -noout -dates
```

---

## DataPower Flow — Certificate Auto-Update

### Directory structure

```text
./
├── datapower-init.hcl          # one-shot agent config: renders all initial certs and exits
├── datapower.hcl               # continuous agent config: renews demo cert and uploads to DataPower
├── templates/
│   ├── webgui.vtmpl            # WebGUI certificate template
│   ├── dp-ui.vtmpl             # DP-UI certificate template
│   └── demo.vtmpl              # Demo TLS certificate template
├── datapower/
│   ├── start-datapower.sh
│   ├── upload-certs-to-datapower.sh
│   ├── certs/
│   ├── config/
│   └── local/
```

### Step 1 — Generate initial certificates

Run Vault Agent once from the repository root to render the initial certificate set before starting DataPower:

```bash
vault agent -log-level debug -config=./datapower-init.hcl -exit-after-auth
```

[`datapower-init.hcl`](datapower-init.hcl) renders:

- `templates/webgui.vtmpl` → `certs/webgui.out`
- `templates/dp-ui.vtmpl` → `certs/dp-ui.out`
- `templates/demo.vtmpl` → `certs/demo.out`

### Step 2 — Start DataPower

```bash
cd datapower
bash ./start-datapower.sh
```

[`datapower/start-datapower.sh`](datapower/start-datapower.sh) starts the container and mounts `config/`, `local/`, and `certs/`.

Exposed endpoints:

| Endpoint              | URL                        |
| --------------------- | -------------------------- |
| Web UI                | `https://localhost:9090`   |
| SOMA API              | `https://localhost:5550`   |
| REST Management API   | `https://localhost:5554`   |
| Demo TLS service      | `https://localhost:8043`   |

Default credentials: `admin` / `admin`.

### Step 3 — Run continuous Vault Agent updates

```bash
vault agent -log-level debug -config=./datapower.hcl
```

[`datapower.hcl`](datapower.hcl) continuously renders `templates/demo.vtmpl` → `certs/demo.out` and runs [`datapower/upload-certs-to-datapower.sh`](datapower/upload-certs-to-datapower.sh) after each renewal.

### Authentication options

[`datapower.hcl`](datapower.hcl) uses `token_file` by default, reading from `.vault-token`. Commented examples for Kubernetes and AWS auth are included in the file.

#### Token file (default)

```hcl
method {
  type = "token_file"

  config = {
    token_file_path = ".vault-token"
  }
}
```

#### Kubernetes auth

```hcl
# method {
#   type       = "kubernetes"
#   mount_path = "auth/kubernetes"
#   config = {
#     role = "datapower-role"
#   }
# }
```

#### AWS auth

```hcl
# method {
#   type       = "aws"
#   mount_path = "auth/aws"
#   config = {
#     type = "iam"
#     role = "datapower-role"
#   }
# }
```

### DataPower upload behavior

[`datapower/upload-certs-to-datapower.sh`](datapower/upload-certs-to-datapower.sh) uploads certificate files to the DataPower filestore via `PUT /mgmt/filestore/default/cert/{filename}` using basic auth.

Default environment values:

| Variable            | Default     |
| ------------------- | ----------- |
| `DATAPOWER_HOST`    | `localhost` |
| `DATAPOWER_PORT`    | `5554`      |
| `DATAPOWER_USER`    | `admin`     |
| `DATAPOWER_PASSWORD`| `admin`     |

Files uploaded:

- `certs/demo-sscert.pem` → `demo-sscert.pem`
- `certs/demo-privkey.pem` → `demo-privkey.pem`

### Useful commands

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
curl -k -u admin:admin https://localhost:5554/mgmt/filestore/default/cert/
```

### Troubleshooting

**Vault Agent exits immediately** — If `-exit-after-auth` was passed, this is expected for the initial one-shot render.

**No certificates generated** — Verify Vault dev server is running on `http://127.0.0.1:8200`, PKI is configured via Terraform, `.vault-token` exists at the repo root, and the templates reference valid PKI paths.

**Upload to DataPower fails** — Verify DataPower is running, REST Management API is reachable on `https://localhost:5554`, credentials match the container, and the expected cert files exist in `certs/`.

**TLS warnings from curl** — [`datapower/upload-certs-to-datapower.sh`](datapower/upload-certs-to-datapower.sh) uses `curl -k`, which disables certificate verification for local testing.

---

## Teardown

```bash
cd terraform
terraform destroy
```
