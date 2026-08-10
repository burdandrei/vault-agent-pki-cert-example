pid_file = "./pidfile"

vault {
  address = "http://127.0.0.1:8200"
}

auto_auth {
  method {
    type = "token_file"

    config = {
      token_file_path = ".vault-token"
    }
  }
}

# Vault Agent continuously renews the certificate via the PKI secrets engine
# and writes the individual PEM files.  On each renewal the exec block calls
# reload-haproxy.sh, which:
#   1. Assembles certs/haproxy-bundle.pem (key + cert + chain)
#   2. Validates the HAProxy config
#   3. Gracefully reloads HAProxy with the new bundle
#
# Run haproxy-init.hcl with -exit-after-auth first to populate the initial
# certificate files before starting HAProxy.
template {
  source      = "templates/haproxy-cert.vtmpl"
  destination = "certs/haproxy-cert.pem"

  exec {
    command = ["bash", "haproxy/reload-haproxy.sh"]
    timeout = "30s"
  }
}
