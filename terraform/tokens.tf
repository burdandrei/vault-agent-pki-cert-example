# ---------------------------------------------------------------------------
# Token auth backend roles — one per issuer
# Each role locks the token to exactly the corresponding ACL policy.
# ---------------------------------------------------------------------------

resource "vault_token_auth_backend_role" "datapower" {
  role_name        = "datapower"
  allowed_policies = [vault_policy.datapower.name]
  orphan           = true
  renewable        = true
  token_ttl        = 3600
  token_max_ttl    = 86400
  token_type       = "service"
}

resource "vault_token_auth_backend_role" "nginx" {
  role_name        = "nginx"
  allowed_policies = [vault_policy.nginx.name]
  orphan           = true
  renewable        = true
  token_ttl        = 3600
  token_max_ttl    = 86400
  token_type       = "service"
}

resource "vault_token_auth_backend_role" "haproxy" {
  role_name        = "haproxy"
  allowed_policies = [vault_policy.haproxy.name]
  orphan           = true
  renewable        = true
  token_ttl        = 3600
  token_max_ttl    = 86400
  token_type       = "service"
}

# ---------------------------------------------------------------------------
# Mint one service token per issuer — written to the repo root so each
# Vault Agent config (datapower.hcl, nginx.hcl, haproxy.hcl) can read it.
#
# vault_token (resource) is used instead of the ephemeral block because
# ephemeral blocks are evaluated at plan time, before the
# vault_token_auth_backend_role resources exist in Vault, which causes a
# 400 "unknown role" error on every plan/apply.
# ---------------------------------------------------------------------------

resource "vault_token" "datapower" {
  role_name   = vault_token_auth_backend_role.datapower.role_name
  policies    = [vault_policy.datapower.name]
  ttl         = "1h"
  display_name = "datapower-agent"
  renewable   = true
  no_parent   = true

  depends_on = [vault_token_auth_backend_role.datapower]
}

resource "vault_token" "nginx" {
  role_name   = vault_token_auth_backend_role.nginx.role_name
  policies    = [vault_policy.nginx.name]
  ttl         = "1h"
  display_name = "nginx-agent"
  renewable   = true
  no_parent   = true

  depends_on = [vault_token_auth_backend_role.nginx]
}

resource "vault_token" "haproxy" {
  role_name   = vault_token_auth_backend_role.haproxy.role_name
  policies    = [vault_policy.haproxy.name]
  ttl         = "1h"
  display_name = "haproxy-agent"
  renewable   = true
  no_parent   = true

  depends_on = [vault_token_auth_backend_role.haproxy]
}

# ---------------------------------------------------------------------------
# Write each token to the repo root (mode 0600, sensitive)
# ---------------------------------------------------------------------------

resource "local_sensitive_file" "vault_token_datapower" {
  filename        = "${path.module}/../.vault-token-datapower"
  content         = vault_token.datapower.client_token
  file_permission = "0600"
}

resource "local_sensitive_file" "vault_token_nginx" {
  filename        = "${path.module}/../.vault-token-nginx"
  content         = vault_token.nginx.client_token
  file_permission = "0600"
}

resource "local_sensitive_file" "vault_token_haproxy" {
  filename        = "${path.module}/../.vault-token-haproxy"
  content         = vault_token.haproxy.client_token
  file_permission = "0600"
}
