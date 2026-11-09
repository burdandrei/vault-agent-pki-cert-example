pid_file = "./pidfile-netscaler"

vault {
  address = "http://127.0.0.1:8200"
}

auto_auth {
  method {
    type = "token_file"

    config = {
      token_file_path = ".vault-token-netscaler"
    }
  }
}

# Vault Agent continuously renews the certificate via the PKI secrets engine
# and writes the individual PEM files.  On each renewal the exec block calls
# upload-certs-to-netscaler.sh, which:
#   1. Uploads certs/netscaler-cert.pem and certs/netscaler-privkey.pem to
#      the NetScaler /nsconfig/ssl/ filestore via the NITRO systemfile API.
#   2. Updates the SSL certkey object "vault-demo" so NetScaler immediately
#      re-reads the new material and pushes it to all bound virtual servers.
#   3. Saves the running config so the update persists across restarts.
#
# Bootstrap certs (7-day TTL, terraform.hashicorp.ibm CA) are written by
# `terraform apply` so the container can start before this agent runs.
template {
  source      = "templates/netscaler-cert.vtmpl"
  destination = "certs/netscaler-cert.pem"

  exec {
    command = ["bash", "netscaler/upload-certs-to-netscaler.sh"]
    timeout = "30s"
  }
}

# ---------------------------------------------------------------------------
# Authentication alternatives
#
# The token_file method above reads from .vault-token-netscaler (written by
# `terraform apply`).  For production deployments use one of the methods below.
#
# Kubernetes auth:
# method {
#   type       = "kubernetes"
#   mount_path = "auth/kubernetes"
#   config = {
#     role = "netscaler-role"
#   }
# }
#
# AWS IAM auth:
# method {
#   type       = "aws"
#   mount_path = "auth/aws"
#   config = {
#     type = "iam"
#     role = "netscaler-role"
#   }
# }
# ---------------------------------------------------------------------------
