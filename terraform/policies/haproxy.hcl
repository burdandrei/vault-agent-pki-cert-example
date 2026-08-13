# ACL policy — HAProxy certificate issuance
# Grants the minimum rights needed by an HAProxy Vault Agent to request
# certificates from the intermediate PKI role "haproxy".

path "pki_int/issue/haproxy" {
  capabilities = ["create", "update"]
}

path "pki_int/sign/haproxy" {
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
