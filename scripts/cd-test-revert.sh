#!/usr/bin/env bash
set -euo pipefail

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

# Commit and push
git add prisma/migrations/ app/page.tsx
git diff --cached --quiet || git commit -m "feat: CD test: remove Litecoin and revert heading"
git push origin main

REPO_URL=$(gh repo view --json url -q .url)
echo ""
echo "Pushed. release.yml will cut a new version, then deploy.yml will build,"
echo "run migrations, and wait for approval at:"
echo "  ${REPO_URL}/actions"
