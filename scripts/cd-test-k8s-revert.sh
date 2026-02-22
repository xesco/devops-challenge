#!/usr/bin/env bash
set -euo pipefail

git diff --quiet && git diff --cached --quiet \
  || { echo "Working tree is dirty. Commit or stash changes first." >&2; exit 1; }

HPA="k8s/base/nextjs/hpa.yaml"
DEPLOY="k8s/base/nextjs/deployment.yaml"

# Revert HPA minReplicas 4 -> 2
sed -i 's/minReplicas: 4/minReplicas: 2/' "$HPA"

# Revert liveness probe failureThreshold 6 -> 3
sed -i '/livenessProbe/,/failureThreshold/{s/failureThreshold: 6/failureThreshold: 3/}' "$DEPLOY"

git add "$HPA" "$DEPLOY"
git diff --cached --quiet || git commit -m "CD test (k8s): revert replicas and liveness failureThreshold"
git push origin main

REPO_URL=$(gh repo view --json url -q .url)
echo ""
echo "Pushed. No approval needed - deploys automatically."
echo "  ${REPO_URL}/actions"
echo ""
echo "Verify with:"
echo "  kubectl -n moonpay get hpa"
echo "  kubectl -n moonpay get pods"
