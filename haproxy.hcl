pid_file = "./pidfile-haproxy"

vault {
  address = "http://127.0.0.1:8200"
}

auto_auth {
  method {
    type = "token_file"

    config = {
      token_file_path = ".vault-token-haproxy"
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
# Bootstrap certs (7-day TTL, terraform.hashicorp.ibm CA) are written by
# `terraform apply` so the container can start before this agent runs.
template {
  source      = "templates/haproxy-cert.vtmpl"
  destination = "certs/haproxy-cert.pem"

  exec {
    command = ["bash", "haproxy/reload-haproxy.sh"]
    timeout = "30s"
  }
}
