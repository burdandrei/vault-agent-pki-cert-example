pid_file = "./pidfile"

vault {
  address = "http://127.0.0.1:8200"
}

auto_auth {
  method {
     type = "token_file"

    config = {
      token_file_path = "../.vault-token"
    }
  }

  # Uncomment to use Kubernetes auth instead of token_file.
  # method {
  #   type = "kubernetes"
  #
  #   mount_path = "auth/kubernetes"
  #
  #   config = {
  #     role = "datapower-role"
  #   }
  # }

  # Uncomment to use AWS auth instead of token_file.
  # method {
  #   type = "aws"
  #
  #   mount_path = "auth/aws"
  #
  #   config = {
  #     type = "iam"
  #     role = "datapower-role"
  #   }
  # }

}

template {
  source = "templates/demo.vtmpl"
  destination = "certs/demo.out"
  command = "bash upload-certs-to-datapower.sh"
}