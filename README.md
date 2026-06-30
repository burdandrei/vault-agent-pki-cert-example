# Vault Agent PKI Certificate Example

This example shows how to configure a Vault PKI secrets engine and issue certificates via Vault Agent.
Infrastructure setup (audit device, PKI engine, root CA, and role) is managed with Terraform.

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/downloads) >= 1.3
- [Vault CLI](https://developer.hashicorp.com/vault/downloads)
- A running Vault server (see step 1 below)

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

| Output                | Description                                   |
| --------------------- | --------------------------------------------- |
| `pki_mount_path`      | Mount path of the root PKI engine             |
| `pki_int_mount_path`  | Mount path of the intermediate PKI engine     |
| `root_ca_common_name` | Common name of the root CA                    |
| `role_name`           | PKI role name for issuing certs               |
| `issue_path`          | Vault path for demoissuer certificate issuance |
| `datapower_issue_path`| Vault path for DataPower certificate issuance |

## 4. Start Vault Agent

```bash
vault agent -log-level debug -config=./vault-agent-contents.hcl
```

Vault Agent will use the `issue_path` from the Terraform output (`pki_int/issue/demoissuer`) to periodically request and renew certificates, writing them to `certs/`.

## 5. Verify the issued certificate

```bash
openssl x509 -in certs/cert.pem -noout -dates
```

---

## Teardown

```bash
cd terraform
terraform destroy
```
