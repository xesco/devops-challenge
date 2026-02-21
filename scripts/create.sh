#!/usr/bin/env bash
set -euo pipefail

# ── Colours ──────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m' # No colour

info()  { printf "${BOLD}▸ %s${NC}\n" "$*"; }
ok()    { printf "${GREEN}✔ %s${NC}\n" "$*"; }
warn()  { printf "${YELLOW}⚠ %s${NC}\n" "$*"; }
die()   { printf "${RED}✖ %s${NC}\n" "$*" >&2; exit 1; }

# ── Prerequisites ────────────────────────────────────────────────
info "Checking prerequisites…"

command -v gcloud    >/dev/null 2>&1 || die "gcloud CLI not found. Install: https://cloud.google.com/sdk/docs/install"
command -v terraform >/dev/null 2>&1 || die "terraform not found. Install: mise use -g terraform@latest"
command -v gh        >/dev/null 2>&1 || die "gh CLI not found. Install: mise use -g gh@latest"

gcloud auth print-access-token >/dev/null 2>&1 \
  || die "Not authenticated with gcloud. Run: gcloud auth login"

gh auth status >/dev/null 2>&1 \
  || die "Not authenticated with gh. Run: gh auth login"

[[ -f terraform/terraform.tfvars ]] \
  || die "terraform/terraform.tfvars not found. Copy the example:\n  cp terraform/terraform.tfvars.example terraform/terraform.tfvars"

ok "All prerequisites met"

# ── Derive project settings ──────────────────────────────────────
PROJECT_ID=$(gcloud config get project 2>/dev/null)
[[ -n "${PROJECT_ID}" ]] || die "No GCP project set. Run: gcloud config set project <PROJECT_ID>"

REGION=$(gcloud config get compute/region 2>/dev/null || true)
REGION="${REGION:-us-central1}"

BUCKET="${PROJECT_ID}-tfstate"

export GITHUB_TOKEN
GITHUB_TOKEN=$(gh auth token)

info "Project:  ${PROJECT_ID}"
info "Region:   ${REGION}"
info "State:    gs://${BUCKET}"

# ── GCS state bucket ────────────────────────────────────────────
info "Creating state bucket (idempotent)…"

if gcloud storage buckets describe "gs://${BUCKET}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
  warn "Bucket gs://${BUCKET} already exists — skipping creation"
else
  gcloud storage buckets create "gs://${BUCKET}" \
    --project="${PROJECT_ID}" \
    --location="${REGION}" \
    --uniform-bucket-level-access \
    --public-access-prevention
  gcloud storage buckets update "gs://${BUCKET}" --versioning
  ok "Bucket gs://${BUCKET} created with versioning"
fi

# ── Terraform ────────────────────────────────────────────────────
info "Initialising Terraform…"
terraform -chdir=terraform init -backend-config="bucket=${BUCKET}"

info "Applying Terraform (auto-approve)…"
terraform -chdir=terraform apply -auto-approve

ok "Infrastructure provisioned"

# ── GKE credentials ─────────────────────────────────────────────
info "Fetching GKE credentials…"
gcloud container clusters get-credentials devops-challenge \
  --region "${REGION}" \
  --project "${PROJECT_ID}"

ok "kubectl configured for cluster devops-challenge"

# ── Done ─────────────────────────────────────────────────────────
printf "\n${GREEN}${BOLD}All done!${NC}\n\n"
printf "Push to ${BOLD}main${NC} to trigger the first deploy:\n"
printf "  git push origin main\n\n"
printf "Then approve the deploy in the GitHub UI when prompted.\n"
printf "Once deployed, run ${BOLD}make show-ip${NC} to get the external IP.\n"
