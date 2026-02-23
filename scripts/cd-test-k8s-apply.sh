#!/usr/bin/env bash
set -euo pipefail

DRY_RUN=false
[[ "${1:-}" == "-d" || "${1:-}" == "--dry-run" ]] && DRY_RUN=true

git diff --quiet && git diff --cached --quiet \
  || { echo "Working tree is dirty. Commit or stash changes first." >&2; exit 1; }

HPA="k8s/base/nextjs/hpa.yaml"
DEPLOY="k8s/base/nextjs/deployment.yaml"

# Scale HPA minReplicas 2 -> 4
sed -i.bak 's/minReplicas: 2/minReplicas: 4/' "$HPA" && rm "${HPA}.bak"

# Liveness probe failureThreshold 3 -> 6
sed -i.bak '/livenessProbe/,/failureThreshold/s/failureThreshold: 3/failureThreshold: 6/' "$DEPLOY" && rm "${DEPLOY}.bak"

# Stage and show diff
git add "$HPA" "$DEPLOY"

if $DRY_RUN; then
  echo "[dry-run] Changes that would be committed:"
  echo ""
  git diff --cached
  echo ""
  echo "[dry-run] Commit message: fix: CD test (k8s): scale to 4 replicas and increase liveness failureThreshold"
  # Revert all changes
  git reset HEAD -- . >/dev/null
  git checkout -- . 2>/dev/null
  exit 0
fi

# Commit and push
git diff --cached --quiet || git commit -m "fix: CD test (k8s): scale to 4 replicas and increase liveness failureThreshold"
git pull --rebase origin main
git push origin main

REPO_URL=$(gh repo view --json url -q .url)
echo ""
echo "Pushed. release.yml will cut a new patch release, build images, run migrations,"
echo "and deploy automatically. Follow at:"
echo "  ${REPO_URL}/actions"
echo ""
echo "Verify with:"
echo "  kubectl -n moonpay get hpa"
echo "  kubectl -n moonpay get pods"
