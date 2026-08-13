# ---------------------------------------------------------------------------
# ACL Policies — one per issuer, loaded from terraform/policies/*.hcl
# ---------------------------------------------------------------------------

resource "vault_policy" "datapower" {
  name   = "datapower-pki"
  policy = file("${path.module}/policies/datapower.hcl")
}

resource "vault_policy" "nginx" {
  name   = "nginx-pki"
  policy = file("${path.module}/policies/nginx.hcl")
}

resource "vault_policy" "haproxy" {
  name   = "haproxy-pki"
  policy = file("${path.module}/policies/haproxy.hcl")
}

# ---------------------------------------------------------------------------
# Outputs
# ---------------------------------------------------------------------------

output "datapower_policy_name" {
  description = "Vault ACL policy name for the DataPower issuer."
  value       = vault_policy.datapower.name
}

output "nginx_policy_name" {
  description = "Vault ACL policy name for the nginx issuer."
  value       = vault_policy.nginx.name
}

output "haproxy_policy_name" {
  description = "Vault ACL policy name for the HAProxy issuer."
  value       = vault_policy.haproxy.name
}
