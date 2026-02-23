#!/usr/bin/env bash
set -euo pipefail

DRY_RUN=false
[[ "${1:-}" == "-d" || "${1:-}" == "--dry-run" ]] && DRY_RUN=true

git diff --quiet && git diff --cached --quiet \
  || { echo "Working tree is dirty. Commit or stash changes first." >&2; exit 1; }

# Create migration
TIMESTAMP=$(date +%Y%m%d%H%M%S)
DIR="prisma/migrations/${TIMESTAMP}_cd_test_remove_litecoin"
mkdir -p "$DIR"

cat > "$DIR/migration.sql" <<'SQL'
DELETE FROM "currencies" WHERE "code" = 'ltc';
SQL

# Revert heading
sed -i.bak 's/LatestPrices (CD Test)/LatestPrices/' app/page.tsx && rm app/page.tsx.bak

# Stage and show diff
git add prisma/migrations/ app/page.tsx

if $DRY_RUN; then
  echo "[dry-run] Changes that would be committed:"
  echo ""
  git diff --cached
  echo ""
  echo "[dry-run] Commit message: feat: CD test: remove Litecoin and revert heading"
  # Revert all changes
  git reset HEAD -- . >/dev/null
  git checkout -- . 2>/dev/null
  rm -rf "$DIR"
  exit 0
fi

# Commit and push
git diff --cached --quiet || git commit -m "feat: CD test: remove Litecoin and revert heading"
git pull --rebase origin main
git push origin main

REPO_URL=$(gh repo view --json url -q .url)
echo ""
echo "Pushed. release.yml will cut a new version, build images, run migrations,"
echo "and deploy automatically. Follow at:"
echo "  ${REPO_URL}/actions"
