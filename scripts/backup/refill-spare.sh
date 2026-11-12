#!/usr/bin/env bash
# Refills the spare Supabase project from a data dump of the main one
# (docs/adr/0034-packed-changes-and-backups.md). Every table in the dump is emptied and
# loaded again in ONE transaction: if anything fails, the spare stays exactly as it was.
#
# Usage: SPARE_DB_URL=postgresql://... scripts/backup/refill-spare.sh data.sql
# The spare must already have every file in supabase/migrations run on it.
set -euo pipefail

data="${1:?usage: refill-spare.sh data.sql}"
: "${SPARE_DB_URL:?SPARE_DB_URL is not set}"

# The tables the dump fills, e.g. "public"."sync_change" and "auth"."users".
tables=$(grep -E '^COPY ' "$data" | sed -E 's/^COPY ([^ (]+).*/\1/' | sort -u | paste -sd, - || true)
if [ -z "$tables" ]; then
  echo "The dump has no tables; leaving the spare as it is." >&2
  exit 1
fi

psql "$SPARE_DB_URL" -X -q -v ON_ERROR_STOP=1 --single-transaction >/dev/null <<SQL
set session_replication_role = replica;
truncate $tables cascade;
\i $data
-- Shared-group positions on the spare start far past the main project's, so phones whose
-- place is already past the copy still receive everything uploaded to the spare.
select setval(pg_get_serial_sequence('public.sync_change', 'seq'),
              (select coalesce(max(seq), 0) from public.sync_change) + 10000000);
SQL
echo "Spare refilled ($(echo "$tables" | tr ',' '\n' | wc -l | tr -d ' ') tables)."
