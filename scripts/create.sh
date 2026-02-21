#!/usr/bin/env bash
set -euo pipefail

# Prerequisites
command -v gcloud    >/dev/null 2>&1 || { echo "gcloud CLI not found" >&2; exit 1; }
command -v terraform >/dev/null 2>&1 || { echo "terraform not found" >&2; exit 1; }
command -v kustomize >/dev/null 2>&1 || { echo "kustomize not found. Run: mise use -g kustomize@latest" >&2; exit 1; }
command -v gh        >/dev/null 2>&1 || { echo "gh CLI not found" >&2; exit 1; }
gcloud auth print-access-token >/dev/null 2>&1 \
  || { echo "Not authenticated with gcloud. Run: gcloud auth login" >&2; exit 1; }
gh auth status >/dev/null 2>&1 \
  || { echo "Not authenticated with gh. Run: gh auth login" >&2; exit 1; }
[[ -f terraform/terraform.tfvars ]] \
  || { echo "terraform/terraform.tfvars not found. Run: cp terraform/terraform.tfvars.example terraform/terraform.tfvars" >&2; exit 1; }

# Project settings
PROJECT_ID=$(gcloud config get project 2>/dev/null)
[[ -n "${PROJECT_ID}" ]] || { echo "No GCP project set. Run: gcloud config set project <PROJECT_ID>" >&2; exit 1; }
REGION=$(gcloud config get compute/region 2>/dev/null || true)
REGION="${REGION:-us-central1}"
BUCKET="${PROJECT_ID}-tfstate"
export GITHUB_TOKEN
GITHUB_TOKEN=$(gh auth token)

echo "Project: ${PROJECT_ID}"
echo "Region:  ${REGION}"
echo "State:   gs://${BUCKET}"

# State bucket
if gcloud storage buckets describe "gs://${BUCKET}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
  echo "Bucket gs://${BUCKET} already exists, skipping creation"
else
  gcloud storage buckets create "gs://${BUCKET}" \
    --project="${PROJECT_ID}" \
    --location="${REGION}" \
    --uniform-bucket-level-access \
    --public-access-prevention
  gcloud storage buckets update "gs://${BUCKET}" --versioning
fi

# Terraform
terraform -chdir=terraform init -backend-config="bucket=${BUCKET}"
terraform -chdir=terraform apply -auto-approve

# GKE credentials
CLUSTER_NAME=$(terraform -chdir=terraform output -raw cluster_name)
gcloud container clusters get-credentials "$CLUSTER_NAME" \
  --region "${REGION}" \
  --project "${PROJECT_ID}"

echo ""
echo "Done. Push to main to trigger the first deploy:"
echo "  git push origin main"
