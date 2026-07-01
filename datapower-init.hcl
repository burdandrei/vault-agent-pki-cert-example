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
  source = "templates/dp-webgui.vtmpl"
  destination = "datapower/certs/webgui.out"
}

template {
  source = "templates/dp-ui.vtmpl"
  destination = "datapower/certs/dp-ui.out"
}

template {
  source = "templates/dp-demo.vtmpl"
  destination = "datapower/certs/demo.out"
}