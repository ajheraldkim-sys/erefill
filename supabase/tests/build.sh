#!/usr/bin/env bash
# Builds one rolled-back SQL batch for the Supabase MCP execute_sql tool:
#   supabase/tests/build.sh <script.sql ...> -- <test.sql>
# prints BEGIN; scripts (their own BEGIN/COMMIT removed); _fixtures.sql; test; ROLLBACK;
set -euo pipefail
dir="$(cd "$(dirname "$0")" && pwd)"
scripts=()
while [[ $# -gt 0 && "$1" != "--" ]]; do scripts+=("$1"); shift; done
shift || true
echo "BEGIN;"
for s in "${scripts[@]}"; do
  sed -E '/^(BEGIN|COMMIT);[[:space:]]*$/d' "$s" | tr -d '\r'
done
tr -d '\r' < "$dir/_fixtures.sql"
for t in "$@"; do tr -d '\r' < "$t"; done
echo "ROLLBACK;"
