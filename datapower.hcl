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
  source      = "templates/dp-demo-1m.vtmpl"
  destination = "certs/demo-1m.out"

  exec {
    command = ["bash", "datapower/upload-certs-to-datapower.sh"]
    timeout = "30s"
  }
}