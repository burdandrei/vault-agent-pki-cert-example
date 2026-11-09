# ---------------------------------------------------------------------------
# Bootstrap TLS certificates — pure Terraform TLS, no Vault involvement.
#
# A dedicated self-signed CA ("terraform.hashicorp.ibm") issues all leaf
# certs with a 7-day TTL.  These "pre-Vault" certs let the containers start
# immediately after `terraform apply`; Vault Agent then takes over renewal
# on its own schedule.
#
# Private keys are stored in Terraform state (acceptable for local dev).
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Bootstrap CA
# ---------------------------------------------------------------------------
resource "tls_private_key" "bootstrap_ca" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "tls_self_signed_cert" "bootstrap_ca" {
  private_key_pem = tls_private_key.bootstrap_ca.private_key_pem

  subject {
    common_name  = "terraform.hashicorp.ibm"
    organization = "HashiCorp IBM Demo"
  }

  validity_period_hours = 168 # 7 days
  is_ca_certificate     = true
  set_subject_key_id    = true

  allowed_uses = [
    "cert_signing",
    "crl_signing",
    "digital_signature",
  ]
}

# ---------------------------------------------------------------------------
# Helper locals — shared validity
# ---------------------------------------------------------------------------
locals {
  cert_validity_hours = 168 # 7 days
}

# ---------------------------------------------------------------------------
# DataPower — WebGUI cert
#   CN: webgui.datapower.hashicorp.ibm
#   → datapower/certs/webgui-sscert.pem
#   → datapower/certs/webgui-privkey.pem
#   → datapower/certs/ca.pem  (bootstrap CA, shared)
# ---------------------------------------------------------------------------
resource "tls_private_key" "dp_webgui" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_cert_request" "dp_webgui" {
  private_key_pem = tls_private_key.dp_webgui.private_key_pem
  subject {
    common_name = "webgui.datapower.hashicorp.ibm"
  }
  dns_names = ["webgui.datapower.hashicorp.ibm"]
}

resource "tls_locally_signed_cert" "dp_webgui" {
  cert_request_pem   = tls_cert_request.dp_webgui.cert_request_pem
  ca_private_key_pem = tls_private_key.bootstrap_ca.private_key_pem
  ca_cert_pem        = tls_self_signed_cert.bootstrap_ca.cert_pem

  validity_period_hours = local.cert_validity_hours
  set_subject_key_id    = true
  allowed_uses          = ["server_auth", "digital_signature", "key_encipherment"]
}

resource "local_sensitive_file" "dp_webgui_cert" {
  filename        = "${path.module}/../datapower/certs/webgui-sscert.pem"
  content         = tls_locally_signed_cert.dp_webgui.cert_pem
  file_permission = "0600"
}

resource "local_sensitive_file" "dp_webgui_key" {
  filename        = "${path.module}/../datapower/certs/webgui-privkey.pem"
  content         = tls_private_key.dp_webgui.private_key_pem
  file_permission = "0600"
}

resource "local_file" "dp_ca" {
  filename        = "${path.module}/../datapower/certs/ca.pem"
  content         = tls_self_signed_cert.bootstrap_ca.cert_pem
  file_permission = "0644"
}

# ---------------------------------------------------------------------------
# DataPower — DP-UI cert
#   CN: dp-ui.datapower.hashicorp.ibm
#   → datapower/certs/DP-UI-sscert.pem
#   → datapower/certs/DP-UI-privkey.pem
# ---------------------------------------------------------------------------
resource "tls_private_key" "dp_ui" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_cert_request" "dp_ui" {
  private_key_pem = tls_private_key.dp_ui.private_key_pem
  subject {
    common_name = "dp-ui.datapower.hashicorp.ibm"
  }
  dns_names = ["dp-ui.datapower.hashicorp.ibm"]
}

resource "tls_locally_signed_cert" "dp_ui" {
  cert_request_pem   = tls_cert_request.dp_ui.cert_request_pem
  ca_private_key_pem = tls_private_key.bootstrap_ca.private_key_pem
  ca_cert_pem        = tls_self_signed_cert.bootstrap_ca.cert_pem

  validity_period_hours = local.cert_validity_hours
  set_subject_key_id    = true
  allowed_uses          = ["server_auth", "digital_signature", "key_encipherment"]
}

resource "local_sensitive_file" "dp_ui_cert" {
  filename        = "${path.module}/../datapower/certs/DP-UI-sscert.pem"
  content         = tls_locally_signed_cert.dp_ui.cert_pem
  file_permission = "0600"
}

resource "local_sensitive_file" "dp_ui_key" {
  filename        = "${path.module}/../datapower/certs/DP-UI-privkey.pem"
  content         = tls_private_key.dp_ui.private_key_pem
  file_permission = "0600"
}

# ---------------------------------------------------------------------------
# DataPower — Demo TLS cert
#   CN: demo.datapower.hashicorp.ibm
#   → datapower/certs/demo-sscert.pem
#   → datapower/certs/demo-privkey.pem
# ---------------------------------------------------------------------------
resource "tls_private_key" "dp_demo" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_cert_request" "dp_demo" {
  private_key_pem = tls_private_key.dp_demo.private_key_pem
  subject {
    common_name = "demo.datapower.hashicorp.ibm"
  }
  dns_names = ["demo.datapower.hashicorp.ibm"]
}

resource "tls_locally_signed_cert" "dp_demo" {
  cert_request_pem   = tls_cert_request.dp_demo.cert_request_pem
  ca_private_key_pem = tls_private_key.bootstrap_ca.private_key_pem
  ca_cert_pem        = tls_self_signed_cert.bootstrap_ca.cert_pem

  validity_period_hours = local.cert_validity_hours
  set_subject_key_id    = true
  allowed_uses          = ["server_auth", "digital_signature", "key_encipherment"]
}

resource "local_sensitive_file" "dp_demo_cert" {
  filename        = "${path.module}/../datapower/certs/demo-sscert.pem"
  content         = tls_locally_signed_cert.dp_demo.cert_pem
  file_permission = "0600"
}

resource "local_sensitive_file" "dp_demo_key" {
  filename        = "${path.module}/../datapower/certs/demo-privkey.pem"
  content         = tls_private_key.dp_demo.private_key_pem
  file_permission = "0600"
}

# ---------------------------------------------------------------------------
# nginx cert
#   CN: nginx.hashicorp.ibm
#   → certs/nginx-cert.pem   (cert + bootstrap CA chain)
#   → certs/nginx-privkey.pem
# ---------------------------------------------------------------------------
resource "tls_private_key" "nginx" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_cert_request" "nginx" {
  private_key_pem = tls_private_key.nginx.private_key_pem
  subject {
    common_name = "nginx.hashicorp.ibm"
  }
  dns_names = ["nginx.hashicorp.ibm"]
}

resource "tls_locally_signed_cert" "nginx" {
  cert_request_pem   = tls_cert_request.nginx.cert_request_pem
  ca_private_key_pem = tls_private_key.bootstrap_ca.private_key_pem
  ca_cert_pem        = tls_self_signed_cert.bootstrap_ca.cert_pem

  validity_period_hours = local.cert_validity_hours
  set_subject_key_id    = true
  allowed_uses          = ["server_auth", "digital_signature", "key_encipherment"]
}

resource "local_sensitive_file" "nginx_cert" {
  filename        = "${path.module}/../certs/nginx-cert.pem"
  content         = "${tls_locally_signed_cert.nginx.cert_pem}${tls_self_signed_cert.bootstrap_ca.cert_pem}"
  file_permission = "0644"
}

resource "local_sensitive_file" "nginx_key" {
  filename        = "${path.module}/../certs/nginx-privkey.pem"
  content         = tls_private_key.nginx.private_key_pem
  file_permission = "0600"
}

# ---------------------------------------------------------------------------
# HAProxy cert
#   CN: haproxy.hashicorp.ibm
#   → certs/haproxy-cert.pem    (cert + bootstrap CA chain)
#   → certs/haproxy-privkey.pem
#   → certs/haproxy-bundle.pem  (key + cert + CA — HAProxy combined format)
# ---------------------------------------------------------------------------
resource "tls_private_key" "haproxy" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_cert_request" "haproxy" {
  private_key_pem = tls_private_key.haproxy.private_key_pem
  subject {
    common_name = "haproxy.hashicorp.ibm"
  }
  dns_names = ["haproxy.hashicorp.ibm"]
}

resource "tls_locally_signed_cert" "haproxy" {
  cert_request_pem   = tls_cert_request.haproxy.cert_request_pem
  ca_private_key_pem = tls_private_key.bootstrap_ca.private_key_pem
  ca_cert_pem        = tls_self_signed_cert.bootstrap_ca.cert_pem

  validity_period_hours = local.cert_validity_hours
  set_subject_key_id    = true
  allowed_uses          = ["server_auth", "digital_signature", "key_encipherment"]
}

resource "local_sensitive_file" "haproxy_cert" {
  filename        = "${path.module}/../certs/haproxy-cert.pem"
  content         = "${tls_locally_signed_cert.haproxy.cert_pem}${tls_self_signed_cert.bootstrap_ca.cert_pem}"
  file_permission = "0644"
}

resource "local_sensitive_file" "haproxy_key" {
  filename        = "${path.module}/../certs/haproxy-privkey.pem"
  content         = tls_private_key.haproxy.private_key_pem
  file_permission = "0600"
}

resource "local_sensitive_file" "haproxy_bundle" {
  filename        = "${path.module}/../certs/haproxy-bundle.pem"
  content         = "${tls_private_key.haproxy.private_key_pem}${tls_locally_signed_cert.haproxy.cert_pem}${tls_self_signed_cert.bootstrap_ca.cert_pem}"
  file_permission = "0600"
}

# ---------------------------------------------------------------------------
# NetScaler cert
#   CN: netscaler.hashicorp.ibm
#   → certs/netscaler-cert.pem    (cert + bootstrap CA chain)
#   → certs/netscaler-privkey.pem
# ---------------------------------------------------------------------------
resource "tls_private_key" "netscaler" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_cert_request" "netscaler" {
  private_key_pem = tls_private_key.netscaler.private_key_pem
  subject {
    common_name = "netscaler.hashicorp.ibm"
  }
  dns_names = ["netscaler.hashicorp.ibm"]
}

resource "tls_locally_signed_cert" "netscaler" {
  cert_request_pem   = tls_cert_request.netscaler.cert_request_pem
  ca_private_key_pem = tls_private_key.bootstrap_ca.private_key_pem
  ca_cert_pem        = tls_self_signed_cert.bootstrap_ca.cert_pem

  validity_period_hours = local.cert_validity_hours
  set_subject_key_id    = true
  allowed_uses          = ["server_auth", "digital_signature", "key_encipherment"]
}

resource "local_sensitive_file" "netscaler_cert" {
  filename        = "${path.module}/../certs/netscaler-cert.pem"
  content         = "${tls_locally_signed_cert.netscaler.cert_pem}${tls_self_signed_cert.bootstrap_ca.cert_pem}"
  file_permission = "0644"
}

resource "local_sensitive_file" "netscaler_key" {
  filename        = "${path.module}/../certs/netscaler-privkey.pem"
  content         = tls_private_key.netscaler.private_key_pem
  file_permission = "0600"
}
