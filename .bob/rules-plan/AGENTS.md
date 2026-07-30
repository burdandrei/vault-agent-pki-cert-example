# Project Architecture Rules (Non-Obvious Only)

- The three flows (basic, DataPower, nginx) are completely independent — they share only the PKI backend provisioned by Terraform and the `.vault-token` auth method.
- Certificate lifecycle has two phases for DataPower: **init** (`datapower-init.hcl -exit-after-auth`, one-shot, writes to `datapower/certs/`) and **continuous** (`datapower.hcl`, runs indefinitely, also writes to `datapower/certs/` + triggers upload script). The container must be started between these two phases.
- DataPower's TLS hot-reload is a 3-step API sequence: file upload → CryptoCertificate PUT → CryptoKey PUT → SaveConfig POST. Skipping SaveConfig means the reloaded objects are lost on container restart.
- Vault Agent `exec` blocks are **blocking** — the next cert render won't start until the exec command exits. The 30s `timeout` in all exec blocks is therefore a hard ceiling on upload time before Vault Agent errors.
- All three roles (`demoissuer`, `datapower`, `nginx`) issue from the intermediate CA at `pki_int`, not directly from the root CA at `pki`. Adding a new service requires a new role on `pki_int` only.
- Terraform state is local (no backend configured) — the `terraform/` directory holds live state files. `cleanup.sh` deletes them, requiring `terraform apply` again after cleanup.
- The DataPower image is `icr.io/cpopen/datapower/datapower-limited:11.0.0.1` (IBM Container Registry), requires `--platform linux/amd64` (no ARM native image), and uses Podman (not Docker) in `start-datapower.sh`.
