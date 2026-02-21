#!/usr/bin/env bash
set -euo pipefail

git diff --quiet && git diff --cached --quiet && test -z "$(git ls-files --others --exclude-standard)" \
  || { echo "Working tree is dirty. Commit or stash changes first." >&2; exit 1; }

# Create migration
TIMESTAMP=$(date +%Y%m%d%H%M%S)
DIR="prisma/migrations/${TIMESTAMP}_cd_test_remove_litecoin"
mkdir -p "$DIR"

cat > "$DIR/migration.sql" <<'SQL'
DELETE FROM "currencies" WHERE "code" = 'ltc';
SQL

# Revert heading
sed -i 's/LatestPrices (CD Test)/LatestPrices/' app/page.tsx

# Commit and push
git add prisma/migrations/ app/page.tsx
git diff --cached --quiet || git commit -m "CD test: remove Litecoin and revert heading"
git push origin main

REPO_URL=$(gh repo view --json url -q .url)
echo ""
echo "Pushed. Approve the deploy at:"
echo "  ${REPO_URL}/actions"
