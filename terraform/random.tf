resource "random_password" "postgres" {
  length  = 32
  special = false # Avoid URL-encoding issues in POSTGRES_PRISMA_URL
}
