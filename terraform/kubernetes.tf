# Authenticate to GKE so the kubernetes provider can manage in-cluster resources
data "google_client_config" "default" {}

provider "kubernetes" {
  host                   = "https://${google_container_cluster.main.endpoint}"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(google_container_cluster.main.master_auth[0].cluster_ca_certificate)
}

resource "kubernetes_namespace_v1" "moonpay" {
  metadata {
    name = "moonpay"
  }
}

# Connection details for the Cloud SQL Auth Proxy and the app
resource "kubernetes_secret_v1" "postgres_connection" {
  metadata {
    name      = "postgres-connection"
    namespace = kubernetes_namespace_v1.moonpay.metadata[0].name
  }

  data = {
    POSTGRES_PRISMA_URL      = "postgres://postgres:${random_password.postgres.result}@127.0.0.1:5432/currencies?schema=public"
    INSTANCE_CONNECTION_NAME = google_sql_database_instance.postgres.connection_name
  }
}

# SA key JSON mounted into the Cloud SQL Auth Proxy sidecar
resource "kubernetes_secret_v1" "cloudsql_credentials" {
  metadata {
    name      = "cloudsql-credentials"
    namespace = kubernetes_namespace_v1.moonpay.metadata[0].name
  }

  data = {
    "credentials.json" = base64decode(google_service_account_key.cloudsql_client_key.private_key)
  }
}
