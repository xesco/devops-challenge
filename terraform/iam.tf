# Service account for GitHub Actions CI/CD
resource "google_service_account" "deployer" {
  account_id   = "github-actions-deployer"
  display_name = "GitHub Actions Deployer"

  depends_on = [google_project_service.apis]
}

# Push images to Artifact Registry
resource "google_project_iam_member" "deployer_ar_writer" {
  project = var.project_id
  role    = "roles/artifactregistry.writer"
  member  = "serviceAccount:${google_service_account.deployer.email}"
}

# Deploy workloads to GKE
resource "google_project_iam_member" "deployer_gke_developer" {
  project = var.project_id
  role    = "roles/container.developer"
  member  = "serviceAccount:${google_service_account.deployer.email}"
}

# SA key for GitHub Actions - key material lives in local state
resource "google_service_account_key" "deployer_key" {
  service_account_id = google_service_account.deployer.name
}
