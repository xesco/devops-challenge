#!/usr/bin/env bash
set -euo pipefail

git diff --quiet && git diff --cached --quiet \
  || { echo "Working tree is dirty. Commit or stash changes first." >&2; exit 1; }

HPA="k8s/base/nextjs/hpa.yaml"
DEPLOY="k8s/base/nextjs/deployment.yaml"

# Scale HPA minReplicas 2 -> 4
sed -i.bak 's/minReplicas: 2/minReplicas: 4/' "$HPA" && rm "${HPA}.bak"

# Liveness probe failureThreshold 3 -> 6
sed -i.bak '/livenessProbe/,/failureThreshold/{s/failureThreshold: 3/failureThreshold: 6/}' "$DEPLOY" && rm "${DEPLOY}.bak"

git add "$HPA" "$DEPLOY"
git diff --cached --quiet || git commit -m "CD test (k8s): scale to 4 replicas and increase liveness failureThreshold"
git push origin main

REPO_URL=$(gh repo view --json url -q .url)
echo ""
echo "Pushed. No approval needed - deploys automatically."
echo "  ${REPO_URL}/actions"
echo ""
echo "Verify with:"
echo "  kubectl -n moonpay get hpa"
echo "  kubectl -n moonpay get pods"
