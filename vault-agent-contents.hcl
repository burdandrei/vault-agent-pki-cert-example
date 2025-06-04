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
  source = "source.vtmpl"
  destination = "destination"
  command = "echo 'Template rendered successfully!'"
}

