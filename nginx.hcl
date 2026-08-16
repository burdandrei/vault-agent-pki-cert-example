pid_file = "./pidfile-nginx"

vault {
  address = "http://127.0.0.1:8200"
}

auto_auth {
  method {
    type = "token_file"

    config = {
      token_file_path = ".vault-token-nginx"
    }
  }
}

template {
  source      = "templates/nginx-cert.vtmpl"
  destination = "certs/nginx-cert.pem"

  exec {
    command = ["bash", "nginx/reload-nginx.sh"]
    timeout = "30s"
  }
}
