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

command -v gcloud    >/dev/null 2>&1 || die "gcloud CLI not found"
command -v terraform >/dev/null 2>&1 || die "terraform not found"
command -v gh        >/dev/null 2>&1 || die "gh CLI not found"

gcloud auth print-access-token >/dev/null 2>&1 \
  || die "Not authenticated with gcloud. Run: gcloud auth login"

gh auth status >/dev/null 2>&1 \
  || die "Not authenticated with gh. Run: gh auth login"

ok "All prerequisites met"

# ── Derive project settings ──────────────────────────────────────
PROJECT_ID=$(gcloud config get project 2>/dev/null)
[[ -n "${PROJECT_ID}" ]] || die "No GCP project set. Run: gcloud config set project <PROJECT_ID>"

BUCKET="${PROJECT_ID}-tfstate"

export GITHUB_TOKEN
GITHUB_TOKEN=$(gh auth token)

info "Project:  ${PROJECT_ID}"
info "State:    gs://${BUCKET}"

printf "\n${RED}${BOLD}This will destroy ALL infrastructure:${NC}\n"
printf "  • GKE cluster, Artifact Registry, Service Account\n"
printf "  • GitHub environment and secrets\n"
printf "  • Kubernetes namespace and database credentials\n"
printf "  • Terraform state bucket (gs://${BUCKET})\n\n"

# ── Terraform destroy ────────────────────────────────────────────
info "Initialising Terraform…"
terraform -chdir=terraform init -backend-config="bucket=${BUCKET}"

info "Destroying infrastructure (auto-approve)…"
terraform -chdir=terraform destroy -auto-approve

ok "Terraform resources destroyed"

# ── Delete state bucket ──────────────────────────────────────────
info "Deleting state bucket gs://${BUCKET}…"

if gcloud storage buckets describe "gs://${BUCKET}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
  gcloud storage rm -r "gs://${BUCKET}"
  ok "State bucket deleted"
else
  warn "Bucket gs://${BUCKET} not found — already deleted"
fi

# ── Done ─────────────────────────────────────────────────────────
printf "\n${GREEN}${BOLD}Teardown complete.${NC}\n\n"
printf "All GCP resources and the Terraform state bucket have been removed.\n"
printf "To recreate, run ${BOLD}make create${NC}.\n"
