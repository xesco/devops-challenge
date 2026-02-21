#!/usr/bin/env bash
set -euo pipefail

HPA="k8s/base/nextjs/hpa.yaml"
DEPLOY="k8s/base/nextjs/deployment.yaml"

# Scale HPA minReplicas 2 -> 4
sed -i 's/minReplicas: 2/minReplicas: 4/' "$HPA"

# Liveness probe periodSeconds 30 -> 15
sed -i 's/periodSeconds: 30/periodSeconds: 15/' "$DEPLOY"

git add "$HPA" "$DEPLOY"
git commit -m "CD test (k8s): scale to 4 replicas and tighten liveness probe"
git push origin main

REPO_URL=$(gh repo view --json url -q .url)
echo ""
echo "Pushed. No approval needed — deploys automatically."
echo "  ${REPO_URL}/actions"
echo ""
echo "Verify with:"
echo "  kubectl -n moonpay get hpa"
echo "  kubectl -n moonpay get pods"
