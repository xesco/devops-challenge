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

resource "kubernetes_secret_v1" "postgres_credentials" {
  metadata {
    name      = "postgres-credentials"
    namespace = kubernetes_namespace_v1.moonpay.metadata[0].name
  }

  data = {
    POSTGRES_USER     = "postgres"
    POSTGRES_PASSWORD = random_password.postgres.result
    POSTGRES_DB       = "currencies"
  }
}
