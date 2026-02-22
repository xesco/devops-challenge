#!/usr/bin/env bash
set -euo pipefail

git diff --quiet && git diff --cached --quiet \
  || { echo "Working tree is dirty. Commit or stash changes first." >&2; exit 1; }

ICON="data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHdpZHRoPSIzMiIgaGVpZ2h0PSIzMiI+PGcgZmlsbD0ibm9uZSIgZmlsbC1ydWxlPSJldmVub2RkIj48Y2lyY2xlIGN4PSIxNiIgY3k9IjE2IiByPSIxNiIgZmlsbD0iIzM0NUQ5RCIvPjxwYXRoIGZpbGw9IiNGRkYiIGZpbGwtcnVsZT0ibm9uemVybyIgZD0iTTEwLjUgMjR2LTEuMmwxLjUtLjZWMTZsLTEuNS42LS40LTEuMiAxLjktLjhWOGgyLjZ2NS40bDEuOS0uOC40IDEuMi0yLjMuOXY1bDYuOS0yLjh2My4xSDEwLjV6Ii8+PC9nPjwvc3ZnPgo="

# Create migration
TIMESTAMP=$(date +%Y%m%d%H%M%S)
DIR="prisma/migrations/${TIMESTAMP}_cd_test_add_litecoin"
mkdir -p "$DIR"

cat > "$DIR/migration.sql" <<SQL
INSERT INTO "currencies" ("name", "code", "icon", "price")
VALUES ('Litecoin', 'ltc', '${ICON}', 84.12)
ON CONFLICT ("code") DO NOTHING;
SQL

# Mark heading (idempotent - skip if already tagged)
grep -q '(CD Test)' app/page.tsx || { sed -i.bak 's/LatestPrices/LatestPrices (CD Test)/' app/page.tsx && rm app/page.tsx.bak; }

# Commit and push
git add prisma/migrations/ app/page.tsx
git diff --cached --quiet || git commit -m "CD test: add Litecoin and mark heading"
git push origin main

REPO_URL=$(gh repo view --json url -q .url)
echo ""
echo "Pushed. Approve the deploy at:"
echo "  ${REPO_URL}/actions"
