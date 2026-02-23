# GitHub Actions configuration - repository secrets
# Authenticates via the GITHUB_TOKEN env var

# Repository secrets - wires GCP credentials into GitHub Actions
resource "github_actions_secret" "gcp_sa_key" {
  repository      = var.github_repository
  secret_name     = "GCP_SA_KEY"
  plaintext_value = base64decode(google_service_account_key.deployer_key.private_key)
}

resource "github_actions_secret" "gcp_project_id" {
  repository      = var.github_repository
  secret_name     = "GCP_PROJECT_ID"
  plaintext_value = var.project_id
}
