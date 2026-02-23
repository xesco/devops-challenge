#!/usr/bin/env bash
set -euo pipefail

command -v gcloud    >/dev/null 2>&1 || { echo "gcloud CLI not found" >&2; exit 1; }
command -v kubectl   >/dev/null 2>&1 || { echo "kubectl not found" >&2; exit 1; }
command -v kustomize >/dev/null 2>&1 || { echo "kustomize not found" >&2; exit 1; }

PROJECT_ID=$(gcloud config get project 2>/dev/null)
[[ -n "${PROJECT_ID}" ]] || { echo "No GCP project set" >&2; exit 1; }
REGION=$(gcloud config get compute/region 2>/dev/null || true)
REGION="${REGION:-us-central1}"
REGISTRY="${REGION}-docker.pkg.dev/${PROJECT_ID}/devops-challenge"
OVERLAY="k8s/migration"

if [[ -n "${1:-}" ]]; then
  SHA="${1}"
  echo "Using specified SHA: ${SHA}"
else
  echo "Looking up latest migrator image..."
  SHA=$(gcloud artifacts docker images list "${REGISTRY}/migrator" \
    --include-tags \
    --sort-by=~CREATE_TIME \
    --limit=1 \
    --format='value(tags)' 2>/dev/null)
  [[ -n "${SHA}" ]] || { echo "No migrator image found in Artifact Registry" >&2; exit 1; }
  echo "Latest migrator tag: ${SHA}"
fi

echo "Registry: ${REGISTRY}"
echo "Image:    ${REGISTRY}/migrator:${SHA}"

kubectl -n moonpay delete job prisma-migrate --ignore-not-found

cd "${OVERLAY}"
kustomize edit set image migrator="${REGISTRY}/migrator:${SHA}"
kubectl apply -k .
kustomize edit set image migrator=migrator:latest
git checkout -- kustomization.yaml
