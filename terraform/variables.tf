variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region for all resources"
  type        = string
  default     = "us-central1"
}

# ── GitHub ───────────────────────────────────────────────────────

variable "github_owner" {
  description = "GitHub user or organization that owns the repository"
  type        = string
}

variable "github_repository" {
  description = "GitHub repository name (without the owner prefix)"
  type        = string
}

variable "github_reviewers" {
  description = "GitHub usernames allowed to approve production deployments"
  type        = list(string)
}
