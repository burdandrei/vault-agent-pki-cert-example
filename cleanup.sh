#!/usr/bin/env bash
# cleanup.sh — destroy Terraform-managed Vault config, remove state files,
# and delete all generated certificate and output files.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"

# ---------------------------------------------------------------------------
# 1. Terraform destroy (requires Vault to be running)
# ---------------------------------------------------------------------------
echo "==> Running terraform destroy..."
if command -v terraform &>/dev/null && [ -f "${REPO_ROOT}/terraform/terraform.tfstate" ]; then
  (
    cd "${REPO_ROOT}/terraform"
    terraform destroy -auto-approve
  )
else
  echo "    Skipping: terraform not found or no state file present."
fi

# ---------------------------------------------------------------------------
# 2. Remove Terraform state and backup files
# ---------------------------------------------------------------------------
echo "==> Removing Terraform state files..."
rm -f \
  "${REPO_ROOT}/terraform/terraform.tfstate" \
  "${REPO_ROOT}/terraform/terraform.tfstate.backup"

# ---------------------------------------------------------------------------
# 3. Remove generated .pem files
# ---------------------------------------------------------------------------
echo "==> Removing .pem files..."
find "${REPO_ROOT}" \
  -not -path "${REPO_ROOT}/.git/*" \
  -not -path "${REPO_ROOT}/terraform/.terraform/*" \
  -name "*.pem" \
  -delete

# ---------------------------------------------------------------------------
# 4. Remove generated .out files
# ---------------------------------------------------------------------------
echo "==> Removing .out files..."
find "${REPO_ROOT}" \
  -not -path "${REPO_ROOT}/.git/*" \
  -name "*.out" \
  -delete

echo "==> Done."
