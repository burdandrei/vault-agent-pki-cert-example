# Vault Agent PKI Certificate Example

This repository demonstrates five Vault Agent workflows:

1. **Basic** — Vault Agent requests and renews a PKI certificate from Vault.
2. **DataPower** — Vault Agent generates certificates for IBM DataPower, starts the container, and keeps selected certificates updated via the DataPower REST Management API.
3. **nginx** — Vault Agent provisions TLS certificates for nginx and reloads the server on each renewal.
4. **HAProxy** — Vault Agent provisions TLS certificates for HAProxy and reloads the server on each renewal.
5. **NetScaler** — Vault Agent generates certificates for Citrix NetScaler CPX, starts the container, and keeps the SSL certkey object updated via the NITRO REST API.

Infrastructure (audit device, PKI engine, root CA, intermediate CA, roles, ACL policies, and token auth backend roles) is managed with Terraform.

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/downloads) >= 1.3
- [Vault CLI](https://developer.hashicorp.com/vault/downloads)
- [Podman](https://podman.io/docs/installation) *(nginx, HAProxy, DataPower, and NetScaler flows)*
- IBM DataPower container image access *(DataPower flow only)*
- Citrix NetScaler CPX container image access *(NetScaler flow only)*
- `curl` available *(DataPower and NetScaler flows)*

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
export VAULT_LICENSE_PATH="~/.vault-license.hclic"
```

Vault dev mode also writes the root token to `~/.vault-token`. Copy it to the repo root so Vault Agent can find it:

```bash
cp ~/.vault-token .vault-token
```

## 3. Apply Terraform

The Terraform configuration in `./terraform` provisions:

- File audit device (stdout, raw format)
- Root PKI secrets engine mounted at `pki`
- Root CA (`vault.hashicorp.ibm`, TTL 1 year)
- Intermediate PKI secrets engine mounted at `pki_int` (signed by the root CA)
- PKI role `demoissuer` (allowed domain `demo.vault.hashicorp.ibm`, max TTL 72h)
- PKI role `datapower` (allowed domain `datapower.hashicorp.ibm`, max TTL 72h)
- PKI role `nginx` (allowed domain `nginx.hashicorp.ibm`, max TTL 72h)
- PKI role `haproxy` (allowed domain `haproxy.hashicorp.ibm`, max TTL 72h)
- PKI role `netscaler` (allowed domain `netscaler.hashicorp.ibm`, max TTL 72h)
- ACL policy `datapower-pki` — least-privilege access to `pki_int/issue/datapower` (defined in `terraform/policies/datapower.hcl`)
- ACL policy `nginx-pki` — least-privilege access to `pki_int/issue/nginx` (defined in `terraform/policies/nginx.hcl`)
- ACL policy `haproxy-pki` — least-privilege access to `pki_int/issue/haproxy` (defined in `terraform/policies/haproxy.hcl`)
- ACL policy `netscaler-pki` — least-privilege access to `pki_int/issue/netscaler` (defined in `terraform/policies/netscaler.hcl`)
- Token auth backend role `datapower` — restricts minted tokens to `datapower-pki`
- Token auth backend role `nginx` — restricts minted tokens to `nginx-pki`
- Token auth backend role `haproxy` — restricts minted tokens to `haproxy-pki`
- Token auth backend role `netscaler` — restricts minted tokens to `netscaler-pki`
- Service token for each role, written to `.vault-token-datapower`, `.vault-token-nginx`, `.vault-token-haproxy`, and `.vault-token-netscaler` at the repo root (`chmod 600`)
- Bootstrap TLS certificates for DataPower, nginx, HAProxy, and NetScaler — signed by the `terraform.hashicorp.ibm` CA, 7-day TTL — written directly to `datapower/certs/` and `certs/` so containers can start without a prior Vault Agent run

```bash
cd terraform
terraform init
terraform apply
```

After a successful apply, Terraform prints the outputs:

| Output                        | Description                                              |
| ----------------------------- | -------------------------------------------------------- |
| `pki_mount_path`              | Mount path of the root PKI engine                        |
| `pki_int_mount_path`          | Mount path of the intermediate PKI engine                |
| `root_ca_common_name`         | Common name of the root CA                               |
| `role_name`                   | PKI role name for issuing certs (demoissuer)             |
| `issue_path`                  | Vault path for demoissuer certificate issuance           |
| `datapower_issue_path`        | Vault path for DataPower certificate issuance            |
| `nginx_issue_path`            | Vault path for nginx certificate issuance                |
| `haproxy_issue_path`          | Vault path for HAProxy certificate issuance              |
| `netscaler_issue_path`        | Vault path for NetScaler certificate issuance            |
| `vault_token_datapower_file`  | Path of the token file written for the DataPower agent   |
| `vault_token_nginx_file`      | Path of the token file written for the nginx agent       |
| `vault_token_haproxy_file`    | Path of the token file written for the HAProxy agent     |
| `vault_token_netscaler_file`  | Path of the token file written for the NetScaler agent   |

`terraform apply` also mints one scoped service token per agent role and writes it to the repo root:

| Token file                | Policy attached  | Consumed by             |
| ------------------------- | ---------------- | ----------------------- |
| `.vault-token-datapower`  | `datapower-pki`  | `datapower.hcl`         |
| `.vault-token-nginx`      | `nginx-pki`      | `nginx.hcl`             |
| `.vault-token-haproxy`    | `haproxy-pki`    | `haproxy.hcl`           |
| `.vault-token-netscaler`  | `netscaler-pki`  | `netscaler.hcl`         |

Each file is written with `chmod 600`. To rotate a token, run `terraform apply` again — Terraform will replace the `vault_token` resource and overwrite the file.

---

## Basic Flow — Vault Agent PKI Certificate

### Start Vault Agent

```bash
vault agent -config=./echo.hcl #-log-level debug
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
├── datapower.hcl               # continuous agent config: renews demo cert and uploads to DataPower
├── templates/
│   ├── dp-webgui.vtmpl         # WebGUI certificate template
│   ├── dp-ui.vtmpl             # DP-UI certificate template
│   └── dp-demo.vtmpl           # Demo TLS certificate template
├── datapower/
│   ├── start-datapower.sh
│   ├── upload-certs-to-datapower.sh
│   ├── certs/
│   ├── config/
│   └── local/
```

Bootstrap certificates (signed by `terraform.hashicorp.ibm`, 7-day TTL) are written to `datapower/certs/` by `terraform apply` — no separate init step required.

### Step 1 — Start DataPower

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
vault agent -config=./datapower.hcl #-log-level debug
```

[`datapower.hcl`](datapower.hcl) continuously renders `templates/demo.vtmpl` → `certs/demo.out` and runs [`datapower/upload-certs-to-datapower.sh`](datapower/upload-certs-to-datapower.sh) after each renewal.

### Authentication options

[`datapower.hcl`](datapower.hcl) uses `token_file` by default, reading from `.vault-token-datapower` (written by `terraform apply`). Commented examples for Kubernetes and AWS auth are included in the file.

#### Token file (default)

```hcl
method {
  type = "token_file"

  config = {
    token_file_path = ".vault-token-datapower"
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

**No certificates generated** — Verify Vault dev server is running on `http://127.0.0.1:8200`, PKI is configured via Terraform, the relevant `.vault-token-<service>` file exists, and the templates reference valid PKI paths. Re-run `terraform apply` from `terraform/` to regenerate both tokens and bootstrap certs.

**Upload to DataPower fails** — Verify DataPower is running, REST Management API is reachable on `https://localhost:5554`, credentials match the container, and the expected cert files exist in `certs/`.

**TLS warnings from curl** — [`datapower/upload-certs-to-datapower.sh`](datapower/upload-certs-to-datapower.sh) uses `curl -k`, which disables certificate verification for local testing.

---

## nginx Flow — TLS Certificate Auto-Renewal

Vault Agent provisions a TLS certificate for nginx and reloads the server whenever the certificate is renewed.

### Directory structure

```text
./
├── nginx.hcl                       # Vault Agent config for nginx cert renewal
├── templates/
│   └── nginx-cert.vtmpl            # Vault Agent template — writes cert + chain
├── nginx/
│   ├── nginx.conf                  # nginx config: HTTP→HTTPS redirect + TLS listener
│   ├── start-nginx.sh              # starts the nginx Podman container
│   ├── reload-nginx.sh             # reloads nginx inside the container after cert renewal
│   └── success.html                # page served over HTTPS
```

Bootstrap certificates (signed by `terraform.hashicorp.ibm`, 7-day TTL) are written to `certs/` by `terraform apply` — no separate init step required.

### Step 1 — Start the nginx container

The container mounts `nginx/nginx.conf`, `nginx/success.html`, and `certs/` read-only:

```bash
bash nginx/start-nginx.sh
```

### Step 3 — Run Vault Agent for continuous renewal

```bash
vault agent -log-level debug -config=./nginx.hcl
```

[`nginx.hcl`](nginx.hcl) renders [`templates/nginx-cert.vtmpl`](templates/nginx-cert.vtmpl) to `certs/nginx-cert.pem`, writing the private key to `certs/nginx-privkey.pem` via `writeToFile`, then runs [`nginx/reload-nginx.sh`](nginx/reload-nginx.sh) which sends `nginx -s reload` inside the running container.

### How it works

| File                              | Purpose                                                                      |
| --------------------------------- | ---------------------------------------------------------------------------- |
| `nginx/nginx.conf`                | Port 80 → 301 redirect; port 443 TLS listener; cert paths are `/certs/…`    |
| `nginx/start-nginx.sh`            | Starts `nginx:alpine` container via Podman, mounts config + certs            |
| `nginx/success.html`              | Static HTML page served at `/`                                               |
| `templates/nginx-cert.vtmpl`      | Requests cert from `pki_int/issue/nginx`, writes key + cert+chain            |
| `nginx/reload-nginx.sh`           | Runs `podman exec nginx-vault nginx -s reload` after each cert write         |
| `nginx.hcl`                       | Vault Agent config wiring the above together                                 |

### Verify the certificate

```bash
openssl x509 -in certs/nginx-cert.pem -noout -dates
```

---

## HAProxy Flow — TLS Certificate Auto-Renewal

Vault Agent provisions a TLS certificate for HAProxy and reloads the server whenever the certificate is renewed.

### Directory structure

```text
./
├── haproxy.hcl                     # single agent config: initial render and continuous renewal
├── templates/
│   └── haproxy-cert.vtmpl          # Vault Agent template — writes cert + chain + private key
├── haproxy/
│   ├── haproxy.cfg                 # HAProxy config: TLS frontend using /certs/haproxy-bundle.pem
│   ├── start-haproxy.sh            # starts the HAProxy Podman container
│   ├── reload-haproxy.sh           # assembles bundle and sends SIGHUP to container
│   └── success.html                # page served over HTTPS
```

Bootstrap certificates (signed by `terraform.hashicorp.ibm`, 7-day TTL) including the pre-assembled `certs/haproxy-bundle.pem` are written to `certs/` by `terraform apply` — no separate init step required.

### Step 1 — Start HAProxy

```bash
bash haproxy/start-haproxy.sh
```

The container mounts `haproxy/haproxy.cfg` and `certs/` read-only at `/certs`.

### Step 2 — Run continuous Vault Agent renewal

```bash
vault agent -config=./haproxy.hcl
```

[`haproxy.hcl`](haproxy.hcl) continuously renders [`templates/haproxy-cert.vtmpl`](templates/haproxy-cert.vtmpl) and runs [`haproxy/reload-haproxy.sh`](haproxy/reload-haproxy.sh) after each renewal, which:

1. Reassembles `certs/haproxy-bundle.pem` with the new key and cert
2. Sends `SIGHUP` to the `haproxy-vault` container so it picks up the new bundle

### How it works

| File                           | Purpose                                                                   |
| ------------------------------ | ------------------------------------------------------------------------- |
| `haproxy.hcl`                  | Continuous renewal + reload (bootstrap certs from `terraform apply`)      |
| `haproxy/start-haproxy.sh`     | Starts `haproxy:alpine` container via Podman, mounts config + certs       |
| `haproxy/success.html`         | Static HTML page served at `/`                                            |
| `templates/haproxy-cert.vtmpl` | Requests cert from `pki_int/issue/haproxy`, writes key + cert+chain       |
| `haproxy/reload-haproxy.sh`    | Assembles bundle, sends `podman kill --signal=HUP haproxy-vault`          |
| `haproxy/haproxy.cfg`          | HAProxy config; cert path is `/certs/haproxy-bundle.pem` (container path) |

### Verify the certificate

```bash
openssl x509 -in certs/haproxy-cert.pem -noout -dates
```

---

## NetScaler Flow — Certificate Auto-Update

Vault Agent provisions a TLS certificate for Citrix NetScaler CPX and updates the SSL certkey object via the NITRO REST API whenever the certificate is renewed.

### Directory structure

```text
./
├── netscaler.hcl                       # continuous agent config: renews cert and uploads to NetScaler
├── templates/
│   └── netscaler-cert.vtmpl            # Vault Agent template — writes cert + chain
├── netscaler/
│   ├── start-netscaler.sh              # starts the NetScaler CPX Podman container
│   ├── upload-certs-to-netscaler.sh    # uploads cert+key via NITRO API and updates certkey object
│   └── success.html                    # page served over HTTPS
```

Bootstrap certificates (signed by `terraform.hashicorp.ibm`, 7-day TTL) are written to `certs/` by `terraform apply` — no separate init step required.

### Step 1 — Start the NetScaler CPX container

```bash
bash netscaler/start-netscaler.sh
```

[`netscaler/start-netscaler.sh`](netscaler/start-netscaler.sh) starts the `store/citrix/netscalercpx` container via Podman and mounts `certs/` read-only at `/nsconfig/ssl` — the path NetScaler uses for SSL cert and key files.

Exposed endpoints:

| Endpoint              | URL                           |
| --------------------- | ----------------------------- |
| HTTP (redirect)       | `http://localhost:9080`       |
| HTTPS (TLS)           | `https://localhost:9443`      |
| NITRO REST API        | `http://localhost:32080/nitro/v1/` |

Default credentials: `nsroot` / `nsroot`.

### Step 2 — Run continuous Vault Agent updates

```bash
vault agent -config=./netscaler.hcl #-log-level debug
```

[`netscaler.hcl`](netscaler.hcl) continuously renders [`templates/netscaler-cert.vtmpl`](templates/netscaler-cert.vtmpl) → `certs/netscaler-cert.pem` and runs [`netscaler/upload-certs-to-netscaler.sh`](netscaler/upload-certs-to-netscaler.sh) after each renewal.

### Authentication options

[`netscaler.hcl`](netscaler.hcl) uses `token_file` by default, reading from `.vault-token-netscaler` (written by `terraform apply`). Commented examples for Kubernetes and AWS auth are included in the file.

### NetScaler upload behavior

[`netscaler/upload-certs-to-netscaler.sh`](netscaler/upload-certs-to-netscaler.sh) interacts with the NetScaler NITRO REST API:

1. **Login** — `POST /nitro/v1/config/login` to obtain a session cookie.
2. **Upload files** — `PUT /nitro/v1/config/systemfile/<name>` (falls back to `POST` for first-time creation) to write `netscaler-cert.pem` and `netscaler-privkey.pem` into `/nsconfig/ssl/`.
3. **Update certkey** — `PUT /nitro/v1/config/sslcertkey` to update (or create) the SSL certkey object named `vault-demo`, pointing to the new files. NetScaler immediately pushes the new cert material to all bound virtual servers — no rebind needed.
4. **Save config** — `POST /nitro/v1/config/nsconfig?action=save` so the updated object survives a restart.

Default environment values:

| Variable               | Default     |
| ---------------------- | ----------- |
| `NETSCALER_HOST`       | `localhost` |
| `NETSCALER_PORT`       | `32080`     |
| `NETSCALER_USER`       | `nsroot`    |
| `NETSCALER_PASSWORD`   | `nsroot`    |

Files uploaded and certkey objects updated:

- `certs/netscaler-cert.pem` → `/nsconfig/ssl/netscaler-cert.pem`
- `certs/netscaler-privkey.pem` → `/nsconfig/ssl/netscaler-privkey.pem`
- SSL certkey object: `vault-demo` (cert + key pair; `expirymonitor: ENABLED`)

### How it works

| File                                    | Purpose                                                                                     |
| --------------------------------------- | ------------------------------------------------------------------------------------------- |
| `netscaler.hcl`                         | Continuous renewal + upload (bootstrap certs from `terraform apply`)                        |
| `netscaler/start-netscaler.sh`          | Starts NetScaler CPX container via Podman, mounts `certs/` at `/nsconfig/ssl`               |
| `netscaler/success.html`                | Static HTML page served over HTTPS                                                          |
| `templates/netscaler-cert.vtmpl`        | Requests cert from `pki_int/issue/netscaler`, writes key + cert+chain                       |
| `netscaler/upload-certs-to-netscaler.sh`| Uploads files via NITRO systemfile API, updates `sslcertkey` object, saves config           |

### Useful commands

Check a certificate:

```bash
openssl x509 -in ./certs/netscaler-cert.pem -text -noout
```

Check certificate dates:

```bash
openssl x509 -in ./certs/netscaler-cert.pem -noout -dates
```

Test the NITRO filestore endpoint:

```bash
curl -sf -X POST http://localhost:32080/nitro/v1/config/login \
  -H "Content-Type: application/json" \
  -c /tmp/ns.txt \
  -d '{"login":{"username":"nsroot","password":"nsroot"}}' \
  && curl -sf -b /tmp/ns.txt http://localhost:32080/nitro/v1/config/sslcertkey/vault-demo
```

Verify the certificate served by the live TLS endpoint:

```bash
echo "" | openssl s_client -connect localhost:9443 -showcerts 2>/dev/null \
  | openssl x509 -noout -subject -issuer -dates
```

### Troubleshooting

**No certificates generated** — Verify Vault dev server is running on `http://127.0.0.1:8200`, PKI is configured via Terraform, `.vault-token-netscaler` exists, and the template references a valid PKI path. Re-run `terraform apply` from `terraform/` to regenerate both tokens and bootstrap certs.

**Upload to NetScaler fails** — Verify the NetScaler CPX container is running, NITRO API is reachable on `http://localhost:32080`, credentials match the container, and cert files exist in `certs/`.

**NITRO login returns 401** — The `nsroot` password may have been changed inside the container. Pass `NETSCALER_PASSWORD=<new>` when running the agent, or restart the container from scratch.

---

## Port Reference

All container-based flows use distinct host ports so they can run simultaneously.

| Flow       | Service            | Host port | Container port |
| ---------- | ------------------ | --------- | -------------- |
| nginx      | HTTP (redirect)    | `8080`    | `80`           |
| nginx      | HTTPS (TLS)        | `8443`    | `443`          |
| HAProxy    | HTTP (redirect)    | `8090`    | `8080`         |
| HAProxy    | HTTPS (TLS)        | `8453`    | `8443`         |
| DataPower  | Web UI             | `9090`    | `9090`         |
| DataPower  | SOMA API (SOAP)    | `5550`    | `5550`         |
| DataPower  | REST Mgmt API      | `5554`    | `5554`         |
| DataPower  | Demo TLS service   | `8043`    | `8043`         |
| NetScaler  | HTTP (redirect)    | `9080`    | `9080`         |
| NetScaler  | HTTPS (TLS)        | `9443`    | `9443`         |
| NetScaler  | NITRO REST API     | `32080`   | `32080`        |

---

## Teardown

```bash
cd terraform
terraform destroy
```

The destroy removes all Vault resources managed by Terraform (PKI engines, roles, policies, token auth backend roles, and the minted service tokens).
The token files (`.vault-token-datapower`, `.vault-token-nginx`, `.vault-token-haproxy`, `.vault-token-netscaler`) are also removed by Terraform because they are managed as `local_sensitive_file` resources. Any remaining generated cert files can be removed with `bash ./cleanup.sh`.
