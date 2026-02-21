variable "project_id" {
  description = "GCP project ID"
  type        = string

  validation {
    condition     = length(var.project_id) > 0
    error_message = "project_id must not be empty."
  }
}

variable "region" {
  description = "GCP region for all resources"
  type        = string
  default     = "us-central1"
}

variable "github_owner" {
  description = "GitHub user or organization that owns the repository"
  type        = string

  validation {
    condition     = length(var.github_owner) > 0
    error_message = "github_owner must not be empty."
  }
}

variable "github_repository" {
  description = "GitHub repository name (without the owner prefix)"
  type        = string

  validation {
    condition     = length(var.github_repository) > 0
    error_message = "github_repository must not be empty."
  }
}

variable "github_reviewers" {
  description = "GitHub usernames allowed to approve production deployments"
  type        = list(string)

  validation {
    condition     = length(var.github_reviewers) > 0
    error_message = "github_reviewers must contain at least one username."
  }
}
