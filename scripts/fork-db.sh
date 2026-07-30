#!/usr/bin/env bash
set -euo pipefail

# Fork a PostgreSQL database into: <source_db><suffix>
#
# Usage:
#   ./scripts/fork-db.sh <source_db> <suffix>
#
# Examples:
#   ./scripts/fork-db.sh app_dev _preview
#   # creates: app_dev_preview
#
# Environment variables used by psql/pg_dump/createdb (optional):
#   PGHOST, PGPORT, PGUSER, PGPASSWORD

usage() {
  echo "Usage: $0 <source_db> <suffix>"
  echo "Example: $0 app_dev _preview"
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ $# -ne 2 ]]; then
  usage
  exit 1
fi

SOURCE_DB="$1"
SUFFIX="$2"
TARGET_DB="${SOURCE_DB}${SUFFIX}"

if [[ "$SOURCE_DB" == "$TARGET_DB" ]]; then
  echo "Error: target database name matches source database name"
  exit 1
fi

echo "Checking source database exists: $SOURCE_DB"
if ! psql -d postgres -Atqc "SELECT 1 FROM pg_database WHERE datname='${SOURCE_DB}'" | grep -q '^1$'; then
  echo "Error: source database '$SOURCE_DB' does not exist"
  exit 1
fi

echo "Checking target database does not already exist: $TARGET_DB"
if psql -d postgres -Atqc "SELECT 1 FROM pg_database WHERE datname='${TARGET_DB}'" | grep -q '^1$'; then
  echo "Error: target database '$TARGET_DB' already exists"
  exit 1
fi

echo "Creating target database: $TARGET_DB"
createdb "$TARGET_DB"

echo "Copying data from '$SOURCE_DB' -> '$TARGET_DB'"
pg_dump -d "$SOURCE_DB" --no-owner --no-privileges | psql -d "$TARGET_DB"

echo "Done. Forked database: $TARGET_DB"