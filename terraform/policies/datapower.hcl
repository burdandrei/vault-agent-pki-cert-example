# ACL policy — DataPower certificate issuance
# Grants the minimum rights needed by a DataPower Vault Agent to request
# certificates from the intermediate PKI role "datapower".

path "pki_int/issue/datapower" {
  capabilities = ["create", "update"]
}

path "pki_int/sign/datapower" {
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
