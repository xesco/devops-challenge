# Docker image repository — same region as the cluster for fast pulls
resource "google_artifact_registry_repository" "docker" {
  location      = var.region
  repository_id = "devops-challenge"
  format        = "DOCKER"

  depends_on = [google_project_service.apis]
}
