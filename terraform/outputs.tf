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

output "postgres_password" {
  description = "Auto-generated PostgreSQL password (stored in K8s secret)"
  value       = random_password.postgres.result
  sensitive   = true
}
