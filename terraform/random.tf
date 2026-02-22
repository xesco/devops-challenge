resource "random_password" "postgres" {
  length  = 32
  special = false # Avoid URL-encoding issues in POSTGRES_PRISMA_URL
}

resource "random_id" "cloudsql_suffix" {
  byte_length = 4 # 8 hex chars — avoids Cloud SQL 7-day name reservation on destroy/recreate
}
