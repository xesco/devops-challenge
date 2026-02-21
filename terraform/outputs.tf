output "cluster_name" {
  description = "GKE cluster name"
  value       = google_container_cluster.main.name
}

output "cluster_location" {
  description = "GKE cluster location (region)"
  value       = google_container_cluster.main.location
}

output "artifact_registry_url" {
  description = "Docker registry URL for image pushes"
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.docker.repository_id}"
}

output "deployer_sa_key" {
  description = "SA key JSON — store as GCP_SA_KEY GitHub secret"
  value       = base64decode(google_service_account_key.deployer_key.private_key)
  sensitive   = true
}
