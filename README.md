# Vault Agent PKI Certificate Example

This repository demonstrates four Vault Agent workflows:

1. **Basic** — Vault Agent requests and renews a PKI certificate from Vault.
2. **DataPower** — Vault Agent generates certificates for IBM DataPower, starts the container, and keeps selected certificates updated via the DataPower REST Management API.
3. **nginx** — Vault Agent provisions TLS certificates for nginx and reloads the server on each renewal.
4. **HAProxy** — Vault Agent provisions TLS certificates for HAProxy and reloads the server on each renewal.

Infrastructure (audit device, PKI engine, root CA, intermediate CA, roles, ACL policies, and token auth backend roles) is managed with Terraform.

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/downloads) >= 1.3
- [Vault CLI](https://developer.hashicorp.com/vault/downloads)
- [Podman](https://podman.io/docs/installation) *(nginx, HAProxy, and DataPower flows)*
- IBM DataPower container image access *(DataPower flow only)*
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
- ACL policy `datapower-pki` — least-privilege access to `pki_int/issue/datapower` (defined in `terraform/policies/datapower.hcl`)
- ACL policy `nginx-pki` — least-privilege access to `pki_int/issue/nginx` (defined in `terraform/policies/nginx.hcl`)
- ACL policy `haproxy-pki` — least-privilege access to `pki_int/issue/haproxy` (defined in `terraform/policies/haproxy.hcl`)
- Token auth backend role `datapower` — restricts minted tokens to `datapower-pki`
- Token auth backend role `nginx` — restricts minted tokens to `nginx-pki`
- Token auth backend role `haproxy` — restricts minted tokens to `haproxy-pki`

```bash
cd terraform
terraform init
terraform apply
```

After a successful apply, Terraform prints the outputs:

| Output                  | Description                                    |
| ----------------------- | ---------------------------------------------- |
| `pki_mount_path`        | Mount path of the root PKI engine              |
| `pki_int_mount_path`    | Mount path of the intermediate PKI engine      |
| `root_ca_common_name`   | Common name of the root CA                     |
| `role_name`             | PKI role name for issuing certs (demoissuer)   |
| `issue_path`            | Vault path for demoissuer certificate issuance |
| `datapower_issue_path`  | Vault path for DataPower certificate issuance  |
| `nginx_issue_path`      | Vault path for nginx certificate issuance      |
| `haproxy_issue_path`    | Vault path for HAProxy certificate issuance    |
| `datapower_policy_name` | Name of the DataPower ACL policy               |
| `nginx_policy_name`     | Name of the nginx ACL policy                   |
| `haproxy_policy_name`   | Name of the HAProxy ACL policy                 |

## 4. Issue per-service tokens

Each Vault Agent authenticates with a scoped token that carries only the ACL policy for its PKI role.
Run the helper script from the repo root to mint the three tokens and write them to separate files:

```bash
bash ./issue-tokens.sh
```

| Token file               | Policy attached   | Consumed by                            |
| ------------------------ | ----------------- | -------------------------------------- |
| `.vault-token-datapower` | `datapower-pki`   | `datapower.hcl`, `datapower-init.hcl` |
| `.vault-token-nginx`     | `nginx-pki`       | `nginx.hcl`                            |
| `.vault-token-haproxy`   | `haproxy-pki`     | `haproxy.hcl`                          |

Each file is written `chmod 600`. The script accepts optional environment variables:

| Variable      | Default                   | Description                          |
| ------------- | ------------------------- | ------------------------------------ |
| `VAULT_ADDR`  | `http://127.0.0.1:8200`   | Vault server address                 |
| `VAULT_TOKEN` | `root`                    | Token with permission to mint tokens |
| `TOKEN_TTL`   | `1h`                      | Initial TTL for each issued token    |

Re-run `issue-tokens.sh` any time a token expires or needs rotating.

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
├── datapower-init.hcl          # one-shot agent config: renders all initial certs and exits
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

### Step 1 — Generate initial certificates

Run Vault Agent once from the repository root to render the initial certificate set before starting DataPower:

```bash
vault agent -config=./datapower-init.hcl -exit-after-auth #-log-level debug
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
vault agent -config=./datapower.hcl #-log-level debug
```

[`datapower.hcl`](datapower.hcl) continuously renders `templates/demo.vtmpl` → `certs/demo.out` and runs [`datapower/upload-certs-to-datapower.sh`](datapower/upload-certs-to-datapower.sh) after each renewal.

### Authentication options

[`datapower.hcl`](datapower.hcl) uses `token_file` by default, reading from `.vault-token-datapower` (written by `issue-tokens.sh`). Commented examples for Kubernetes and AWS auth are included in the file.

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

**Vault Agent exits immediately** — If `-exit-after-auth` was passed, this is expected for the initial one-shot render.

**No certificates generated** — Verify Vault dev server is running on `http://127.0.0.1:8200`, PKI is configured via Terraform, the relevant `.vault-token-<service>` file exists (run `bash ./issue-tokens.sh`), and the templates reference valid PKI paths.

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

### Step 1 — Issue the initial certificate

Run Vault Agent once to populate the cert files before starting the container:

```bash
vault agent -config=./nginx.hcl -exit-after-auth
```

### Step 2 — Start the nginx container

The container mounts `nginx/nginx.conf`, `nginx/success.html`, and `certs/` read-only:

```bash
bash nginx/start-nginx.sh
```

### Step 3 — Run Vault Agent for continuous renewal

```bash
vault agent -log-level debug -config=./nginx.hcl
```

[`nginx.hcl`](nginx.hcl) renders [`templates/nginx-cert.vtmpl`](templates/nginx-cert.vtmpl) to `certs/nginx-cert.pem`, writing the private key to `certs/nginx-privkey.pem` via `writeToFile`, then runs [`nginx/reload-nginx.sh`](nginx/reload-nginx.sh) which sends `nginx -s reload` inside the running container. On first run (`-exit-after-auth`) the exec command errors because the container isn't started yet — this is expected.

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

### Step 1 — Generate the initial certificate

Run `haproxy.hcl` with `-exit-after-auth` to populate the cert files before starting HAProxy.
The `exec` block does not fire when the agent exits after auth, so `reload-haproxy.sh` is not called on this run.

```bash
vault agent -config=./haproxy.hcl -exit-after-auth
```

[`haproxy.hcl`](haproxy.hcl) renders [`templates/haproxy-cert.vtmpl`](templates/haproxy-cert.vtmpl), writing:

- `certs/haproxy-cert.pem` — certificate + CA chain (template destination)
- `certs/haproxy-privkey.pem` — private key (written via `writeToFile`)

### Step 2 — Assemble the initial bundle and start HAProxy

Assemble the bundle first so the container has a valid cert on startup, then start the container:

```bash
cat certs/haproxy-privkey.pem certs/haproxy-cert.pem > certs/haproxy-bundle.pem
bash haproxy/start-haproxy.sh
```

The container mounts `haproxy/haproxy.cfg` and `certs/` read-only at `/certs`.

### Step 3 — Run continuous Vault Agent renewal

```bash
vault agent -config=./haproxy.hcl
```

[`haproxy.hcl`](haproxy.hcl) continuously renders [`templates/haproxy-cert.vtmpl`](templates/haproxy-cert.vtmpl) and runs [`haproxy/reload-haproxy.sh`](haproxy/reload-haproxy.sh) after each renewal, which:

1. Reassembles `certs/haproxy-bundle.pem` with the new key and cert
2. Sends `SIGHUP` to the `haproxy-vault` container so it picks up the new bundle

### How it works

| File                           | Purpose                                                                   |
| ------------------------------ | ------------------------------------------------------------------------- |
| `haproxy.hcl`                  | Initial render (`-exit-after-auth`) and continuous renewal + reload       |
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

## Port Reference

All container-based flows use distinct host ports so they can run simultaneously.

| Flow      | Service          | Host port | Container port |
| --------- | ---------------- | --------- | -------------- |
| nginx     | HTTP (redirect)  | `8080`    | `80`           |
| nginx     | HTTPS (TLS)      | `8443`    | `443`          |
| HAProxy   | HTTP (redirect)  | `8090`    | `8080`         |
| HAProxy   | HTTPS (TLS)      | `8453`    | `8443`         |
| DataPower | Web UI           | `9090`    | `9090`         |
| DataPower | SOMA API (SOAP)  | `5550`    | `5550`         |
| DataPower | REST Mgmt API    | `5554`    | `5554`         |
| DataPower | Demo TLS service | `8043`    | `8043`         |

---

## Teardown

```bash
cd terraform
terraform destroy
```

The destroy removes all Vault resources managed by Terraform (PKI engines, roles, policies, token auth backend roles).
The token files (`.vault-token-datapower`, `.vault-token-nginx`, `.vault-token-haproxy`) are not deleted automatically — remove them manually or via `cleanup.sh`.
