#!/usr/bin/env bash
set -euo pipefail

# Prerequisites
command -v gcloud    >/dev/null 2>&1 || { echo "gcloud CLI not found" >&2; exit 1; }
command -v terraform >/dev/null 2>&1 || { echo "terraform not found" >&2; exit 1; }
command -v gh        >/dev/null 2>&1 || { echo "gh CLI not found" >&2; exit 1; }
gcloud auth print-access-token >/dev/null 2>&1 \
  || { echo "Not authenticated with gcloud" >&2; exit 1; }
gh auth status >/dev/null 2>&1 \
  || { echo "Not authenticated with gh" >&2; exit 1; }

# Project settings
PROJECT_ID=$(gcloud config get project 2>/dev/null)
[[ -n "${PROJECT_ID}" ]] || { echo "No GCP project set" >&2; exit 1; }
BUCKET="${PROJECT_ID}-tfstate"
export GITHUB_TOKEN
GITHUB_TOKEN=$(gh auth token)

echo "Project: ${PROJECT_ID}"
echo "State:   gs://${BUCKET}"

# Terraform
terraform -chdir=terraform init -backend-config="bucket=${BUCKET}"
terraform -chdir=terraform destroy -auto-approve

# Delete state bucket
if gcloud storage buckets describe "gs://${BUCKET}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
  gcloud storage rm -r "gs://${BUCKET}"
fi

echo ""
echo "Teardown complete. To recreate, run: make create"
