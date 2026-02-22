INSERT INTO "currencies" ("name", "code", "icon", "price")
VALUES ('Litecoin', 'ltc', 'data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHdpZHRoPSIzMiIgaGVpZ2h0PSIzMiI+PGcgZmlsbD0ibm9uZSIgZmlsbC1ydWxlPSJldmVub2RkIj48Y2lyY2xlIGN4PSIxNiIgY3k9IjE2IiByPSIxNiIgZmlsbD0iIzM0NUQ5RCIvPjxwYXRoIGZpbGw9IiNGRkYiIGZpbGwtcnVsZT0ibm9uemVybyIgZD0iTTEwLjUgMjR2LTEuMmwxLjUtLjZWMTZsLTEuNS42LS40LTEuMiAxLjktLjhWOGgyLjZ2NS40bDEuOS0uOC40IDEuMi0yLjMuOXY1bDYuOS0yLjh2My4xSDEwLjV6Ii8+PC9nPjwvc3ZnPgo=', 84.12)
ON CONFLICT ("code") DO NOTHING;
