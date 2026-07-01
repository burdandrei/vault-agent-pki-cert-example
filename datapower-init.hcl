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
  source = "templates/webgui.vtmpl"
  destination = "certs/webgui.out"
}

template {
  source = "templates/dp-ui.vtmpl"
  destination = "certs/dp-ui.out"
}

template {
  source = "templates/demo.vtmpl"
  destination = "certs/demo.out"
}