# GitHub Actions configuration — environment gate + repository secrets.
# Authenticates via the GITHUB_TOKEN env var.

# Data sources

data "github_user" "reviewers" {
  for_each = toset(var.github_reviewers)
  username = each.value
}

# Production environment.
# Requires manual approval before deploy-app can run.

resource "github_repository_environment" "production" {
  repository  = var.github_repository
  environment = "production"

  reviewers {
    users = [for u in data.github_user.reviewers : u.id]
  }

  deployment_branch_policy {
    protected_branches     = false
    custom_branch_policies = true
  }
}

resource "github_repository_environment_deployment_policy" "main_only" {
  repository     = var.github_repository
  environment    = github_repository_environment.production.environment
  branch_pattern = "main"
}

# Repository secrets.
# Wires the GCP service account key and project ID into GitHub Actions.

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
