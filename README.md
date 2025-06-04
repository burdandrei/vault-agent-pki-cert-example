# Example of running Vault Agent for requesting a PKI Certificate from Vault 

### Start a Vault server in development mode with a fixed root token and debug logging.
```
vault server -dev -dev-root-token-id=root -log-level=DEBUG
```

### Enable file-based audit logging, outputting logs to stdout in raw format.
```
vault audit enable file file_path=stdout log_raw=true
```

### Enable the PKI secrets engine in Vault.
```
vault secrets enable pki
```

### Generate an internal root CA with the common name 'example.ie' and a TTL (validity) of 1 year (8760 hours).
```
vault write pki/root/generate/internal \
    common_name=example.ie \
    ttl=8760h
```

### Create a role 'hc-example-ie' that allows issuing certificates for 'hc.example.ie' and its subdomains, with a maximum TTL of 72 hours.
```
vault write pki/roles/hc-example-ie \
    allowed_domains=hc.example.ie \
    allow_subdomains=true \
    max_ttl=72h
```

### Issue a certificate for 'andrei.hc.example.ie' with a TTL of 3 minutes using the 'hc-example-ie' role.
```
vault write pki/issue/hc-example-ie \
    common_name=andrei.hc.example.ie \
    ttl=3m
```

### Start a Vault agent with debug logging, using the specified configuration file.
```
vault agent -log-level debug -config=./vault-agent-contents.hcl
```

### Display the validity dates of the certificate in 'cert.pem' without showing the certificate content.
```
openssl x509 -in certs/cert.pem -noout -dates
```
