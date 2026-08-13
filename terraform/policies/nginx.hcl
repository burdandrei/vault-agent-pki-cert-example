# ACL policy — nginx certificate issuance
# Grants the minimum rights needed by an nginx Vault Agent to request
# certificates from the intermediate PKI role "nginx".

path "pki_int/issue/nginx" {
  capabilities = ["create", "update"]
}

path "pki_int/sign/nginx" {
  capabilities = ["create", "update"]
}

# Allow reading the intermediate CA certificate (chain validation)
path "pki_int/cert/ca" {
  capabilities = ["read"]
}

# Allow reading CRL
path "pki_int/crl" {
  capabilities = ["read"]
}
