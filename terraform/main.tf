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
    file_path = "stdout"
    log_raw   = "true"
  }
}

# ---------------------------------------------------------------------------
# PKI secrets engine
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
# PKI role
# ---------------------------------------------------------------------------
resource "vault_pki_secret_backend_role" "demoissuer" {
  backend          = vault_mount.pki.path
  name             = "demoissuer"
  allowed_domains  = ["demo.vault.hashicorp.ibm"]
  allow_subdomains = true
  max_ttl          = "72h"
}
