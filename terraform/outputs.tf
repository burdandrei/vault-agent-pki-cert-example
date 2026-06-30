output "pki_mount_path" {
  description = "Path where the PKI secrets engine is mounted."
  value       = vault_mount.pki.path
}

output "root_ca_serial" {
  description = "Serial number of the generated root CA certificate."
  value       = vault_pki_secret_backend_root_cert.root_ca.common_name
}

output "role_name" {
  description = "Name of the PKI role that issues certificates."
  value       = vault_pki_secret_backend_role.demoissuer.name
}

output "issue_path" {
  description = "Full Vault path to use when issuing a certificate (e.g. via vault write or Vault Agent)."
  value       = "${vault_mount.pki.path}/issue/${vault_pki_secret_backend_role.demoissuer.name}"
}
