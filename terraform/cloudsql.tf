# Cloud SQL PostgreSQL instance
resource "google_sql_database_instance" "postgres" {
  name             = "devops-challenge-${random_id.cloudsql_suffix.hex}"
  database_version = "POSTGRES_17"
  region           = var.region

  deletion_protection = false

  settings {
    tier              = "db-f1-micro"
    edition           = "ENTERPRISE"
    availability_type = "ZONAL"
    disk_autoresize   = false
    disk_size         = 10
    disk_type         = "PD_SSD"

    backup_configuration {
      enabled = false
    }

    ip_configuration {
      ipv4_enabled = true
    }
  }

  depends_on = [google_project_service.apis]
}

resource "google_sql_database" "currencies" {
  name     = "currencies"
  instance = google_sql_database_instance.postgres.name
}

resource "google_sql_user" "postgres" {
  name     = "postgres"
  instance = google_sql_database_instance.postgres.name
  password = random_password.postgres.result
}

# Service account used by the Cloud SQL Auth Proxy sidecar
resource "google_service_account" "cloudsql_client" {
  account_id   = "cloudsql-client"
  display_name = "Cloud SQL Auth Proxy Client"

  depends_on = [google_project_service.apis]
}

resource "google_project_iam_member" "cloudsql_client" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.cloudsql_client.email}"
}

resource "google_service_account_key" "cloudsql_client_key" {
  service_account_id = google_service_account.cloudsql_client.name
}
