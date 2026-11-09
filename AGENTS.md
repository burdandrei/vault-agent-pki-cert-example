# AGENTS.md

This file provides guidance to agents when working with code in this repository.

## Stack

- **Infrastructure**: Terraform (HashiCorp Vault provider ≥ 4.0, Terraform ≥ 1.3) — lives in `terraform/`
- **Vault Agent configs**: HCL (`.hcl`) files at the repo root
- **Templates**: Go-template dialect used by Vault Agent (`.vtmpl` files in `templates/`)
- **DataPower container**: Podman (`icr.io/cpopen/datapower/datapower-limited:11.0.0.1`), run via `datapower/start-datapower.sh`
- **NetScaler CPX container**: Podman (`store/citrix/netscalercpx:13.1-51.15`), run via `netscaler/start-netscaler.sh`
- **Shell scripts**: Bash (`cleanup.sh`, `datapower/upload-certs-to-datapower.sh`, `netscaler/upload-certs-to-netscaler.sh`, `nginx/reload-nginx.sh`)

## Critical Commands

```bash
# Bootstrap infrastructure (must run from terraform/ directory)
cd terraform && terraform init && terraform apply

# Basic flow — one-shot cert issuance
vault agent -config=./echo.hcl

# DataPower — step 1: render initial certs before starting container
vault agent -config=./datapower-init.hcl -exit-after-auth

# DataPower — step 2: start container (must run from datapower/ directory)
cd datapower && bash ./start-datapower.sh

# DataPower — step 3: continuous renewal + upload
vault agent -config=./datapower.hcl

# nginx flow
nginx -c "$(pwd)/nginx/nginx.conf"
vault agent -log-level debug -config=./nginx.hcl

# NetScaler flow
bash netscaler/start-netscaler.sh
vault agent -config=./netscaler.hcl

# Teardown
bash ./cleanup.sh   # destroys Terraform state AND deletes all .pem/.out files
```

## Non-Obvious Patterns

### Vault Agent config (`*.hcl`)
- All agents authenticate via `token_file` pointing to `.vault-token` at the repo root (dev mode convenience). Kubernetes and AWS auth examples are commented in `datapower.hcl`.
- The `exec.command` block inside `template {}` runs **after every cert render**, not just on first render. This is how `upload-certs-to-datapower.sh` and `nginx/reload-nginx.sh` are triggered.
- `datapower-init.hcl` is a one-shot config — always add `-exit-after-auth` flag; the `datapower.hcl` is the continuous config.

### Vault Agent templates (`.vtmpl`)
- Templates use the `pkiCert` function: `{{ with pkiCert "<mount>/issue/<role>" "common_name=..." "ttl=..." }}`
- Side-effect file writes use `writeToFile "<path>" "<owner>" "<group>" "<mode>"` piped from `.Key`, `.Cert`, or `.CA`.
- The `.out` destination file (the template's `destination =`) is a "combined" bundle that also echoes key+cert+CA inline — the real per-type files are written via `writeToFile` side effects.
- To build a cert chain (cert + CA): `{{ .Cert | writeToFile "..." "0644" "append" }}` — `append` must be the 5th argument.

### PKI roles and domains (defined in `terraform/main.tf`)
| Role          | Allowed domain                   | Config / Template files                          |
|---------------|----------------------------------|--------------------------------------------------|
| `demoissuer`  | `*.demo.vault.hashicorp.ibm`     | `echo.hcl`, `templates/source.vtmpl`             |
| `datapower`   | `*.datapower.hashicorp.ibm`      | `datapower-init.hcl`, `datapower.hcl`, `templates/dp-*.vtmpl` |
| `nginx`       | `*.nginx.hashicorp.ibm`          | `nginx.hcl`, `templates/nginx-cert.vtmpl`        |
| `haproxy`     | `*.haproxy.hashicorp.ibm`        | `haproxy.hcl`, `templates/haproxy-cert.vtmpl`    |
| `netscaler`   | `*.netscaler.hashicorp.ibm`      | `netscaler.hcl`, `templates/netscaler-cert.vtmpl`|

### DataPower cert upload
- `upload-certs-to-datapower.sh` must be run **from the repo root** (paths are relative: `datapower/certs/demo-sscert.pem`).
- After uploading files, the script calls `reload_cert` and `reload_key` (PUT to `/mgmt/config/default/CryptoCertificate/<name>` and `CryptoKey/<name>`) — without this step, DataPower TLS contexts keep the old cert material in memory even after the file is replaced.
- The DataPower crypto objects are named `demo` (cert), `demo` (key), grouped in idcred `ssl-keystore` (defined in `datapower/config/auto-startup.cfg`).
- `start-datapower.sh` mounts `datapower/certs/` → `/opt/ibm/datapower/root/secure/usrcerts` inside the container, which DataPower maps as `cert:///`.

### nginx cert path coupling
- `nginx/nginx.conf` resolves certs with relative paths `../certs/nginx-cert.pem` and `../certs/nginx-privkey.pem`, which means nginx **must be started from the repo root** using the absolute path form: `nginx -c "$(pwd)/nginx/nginx.conf"`.
- The private key is written via `writeToFile` in `templates/nginx-cert.vtmpl`; the template `destination` file (`certs/nginx-cert.pem`) contains cert + CA chain only.

### NetScaler cert upload
- `upload-certs-to-netscaler.sh` must be run **from the repo root** (paths are relative: `certs/netscaler-cert.pem`).
- The script uses the NITRO REST API: (1) `POST /nitro/v1/config/login` for a session cookie, (2) `PUT /nitro/v1/config/systemfile/<name>` to upload cert and key files into `/nsconfig/ssl/`, (3) `PUT /nitro/v1/config/sslcertkey` to update the `vault-demo` certkey object — this causes NetScaler to push the new material to all bound virtual servers immediately, no rebind required.
- NetScaler CPX NITRO API default credentials: `nsroot` / `nsroot` (override with `NETSCALER_USER` / `NETSCALER_PASSWORD` env vars).
- The volume mount in `start-netscaler.sh` maps `certs/` → `/nsconfig/ssl` read-only; the NITRO upload writes through the API, not via the volume.

### Cleanup
- `cleanup.sh` deletes **all** `*.pem` and `*.out` files across the repo (excluding `.git` and `.terraform` dirs) — do not store generated certs anywhere else in the tree if you want them preserved after cleanup.
