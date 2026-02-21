# Enable required GCP APIs
resource "google_project_service" "apis" {
  for_each = toset([
    "container.googleapis.com",
    "artifactregistry.googleapis.com",
    "iam.googleapis.com",
  ])

  service            = each.value
  disable_on_destroy = false
}

# GKE Autopilot cluster
resource "google_container_cluster" "main" {
  name     = "devops-challenge"
  location = var.region

  enable_autopilot = true

  release_channel {
    channel = "REGULAR"
  }

  # Autopilot manages the default node pool
  deletion_protection = false

  depends_on = [google_project_service.apis]
}
