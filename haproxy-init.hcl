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

# One-shot: render the initial certificate files before starting HAProxy.
# Run with -exit-after-auth so the agent exits once the template is written.
# Subsequent renewals are handled by the continuous haproxy.hcl config.
template {
  source      = "templates/haproxy-cert.vtmpl"
  destination = "certs/haproxy-cert.pem"
}
