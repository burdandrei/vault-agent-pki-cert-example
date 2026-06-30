# ---------------------------------------------------------------------------
# Provider
# ---------------------------------------------------------------------------
provider "vault" {
  address         = "http://127.0.0.1:8200"
  token           = "root"
  skip_tls_verify = true
}

# ---------------------------------------------------------------------------
# Audit device  –  file audit log written to stdout in raw format
# ---------------------------------------------------------------------------
resource "vault_audit" "stdout" {
  type = "file"

  options = {
    file_path = "vault.audit"
    log_raw   = "true"
  }
}

# ---------------------------------------------------------------------------
# Root PKI secrets engine
# ---------------------------------------------------------------------------
resource "vault_mount" "pki" {
  path                      = "pki"
  type                      = "pki"
  default_lease_ttl_seconds = 3600
  max_lease_ttl_seconds     = 315360000 # ~10 years
}

# ---------------------------------------------------------------------------
# Root CA
# ---------------------------------------------------------------------------
resource "vault_pki_secret_backend_root_cert" "root_ca" {
  backend     = vault_mount.pki.path
  type        = "internal"
  common_name = "vault.hashicorp.ibm"
  ttl         = "8760h"
}

# ---------------------------------------------------------------------------
# Intermediate PKI secrets engine
# ---------------------------------------------------------------------------
resource "vault_mount" "pki_int" {
  path                      = "pki_int"
  type                      = "pki"
  default_lease_ttl_seconds = 3600
  max_lease_ttl_seconds     = 157680000 # ~5 years
}

# ---------------------------------------------------------------------------
# Generate a CSR from the intermediate CA
# ---------------------------------------------------------------------------
resource "vault_pki_secret_backend_intermediate_cert_request" "csr" {
  backend     = vault_mount.pki_int.path
  type        = "internal"
  common_name = "vault.hashicorp.ibm Intermediate CA"
}

# ---------------------------------------------------------------------------
# Sign the intermediate CSR with the root CA
# ---------------------------------------------------------------------------
resource "vault_pki_secret_backend_root_sign_intermediate" "signed" {
  backend     = vault_mount.pki.path
  common_name = "vault.hashicorp.ibm Intermediate CA"
  csr         = vault_pki_secret_backend_intermediate_cert_request.csr.csr
  ttl         = "4380h" # ~6 months
}

# ---------------------------------------------------------------------------
# Set the signed certificate back on the intermediate
# ---------------------------------------------------------------------------
resource "vault_pki_secret_backend_intermediate_set_signed" "set" {
  backend     = vault_mount.pki_int.path
  certificate = vault_pki_secret_backend_root_sign_intermediate.signed.certificate
}

# ---------------------------------------------------------------------------
# PKI role – demoissuer (vault-agent-contents.hcl)  –  issues from intermediate
# ---------------------------------------------------------------------------
resource "vault_pki_secret_backend_role" "demoissuer" {
  backend          = vault_mount.pki_int.path
  name             = "demoissuer"
  allowed_domains  = ["demo.vault.hashicorp.ibm"]
  allow_subdomains = true
  max_ttl          = "259200" # 72h
}

# ---------------------------------------------------------------------------
# PKI role – datapower (datapower/templates/*.vtmpl)  –  issues from intermediate
# ---------------------------------------------------------------------------
resource "vault_pki_secret_backend_role" "datapower" {
  backend          = vault_mount.pki_int.path
  name             = "datapower"
  allowed_domains  = ["datapower.hashicorp.ibm"]
  allow_subdomains = true
  max_ttl          = "259200" # 72h
}

# ---------------------------------------------------------------------------
# PKI role – nginx (nginx/templates/nginx-cert.vtmpl)  –  issues from intermediate
# ---------------------------------------------------------------------------
resource "vault_pki_secret_backend_role" "nginx" {
  backend          = vault_mount.pki_int.path
  name             = "nginx"
  allowed_domains  = ["nginx.hashicorp.ibm"]
  allow_subdomains = true
  max_ttl          = "259200" # 72h
}
