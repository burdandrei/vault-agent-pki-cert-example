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

template {
  source      = "templates/source.vtmpl"
  destination = "certs/destination.out"

  exec {
    command = ["bash", "-c", "echo 'Template rendered successfully!' && openssl x509 -in certs/cert.pem -noout -dates"]
    timeout = "30s"
  }
}

