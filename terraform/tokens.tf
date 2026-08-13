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
# To mint a token after apply, use the Vault CLI:
#
#   vault token create -role=datapower -policy=datapower-pki -ttl=1h
#   vault token create -role=nginx     -policy=nginx-pki     -ttl=1h
#   vault token create -role=haproxy   -policy=haproxy-pki   -ttl=1h
#
# ephemeral "vault_token" is NOT used here: ephemeral blocks are evaluated
# at plan time, before the vault_token_auth_backend_role resources exist in
# Vault, which causes a 400 "unknown role" error on every plan/apply.
# ---------------------------------------------------------------------------
