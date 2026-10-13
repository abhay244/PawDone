#!/usr/bin/env bash
# Runs the migrations and schema tests against a throwaway Postgres in Docker.
# Usage: supabase/tests/run.sh
set -euo pipefail
cd "$(dirname "$0")/.."

name=pawdone-schema-test
image=${POSTGRES_IMAGE:-postgres:17.4-alpine}

docker rm -f "$name" >/dev/null 2>&1 || true
docker run -d --name "$name" -e POSTGRES_PASSWORD=postgres "$image" >/dev/null
trap 'docker rm -f "$name" >/dev/null' EXIT

# Wait on TCP: the image's temporary init server only listens on a Unix socket.
until docker exec "$name" pg_isready -h 127.0.0.1 -U postgres >/dev/null 2>&1; do sleep 0.5; done

run_sql() { docker exec -i "$name" psql -h 127.0.0.1 -U postgres -v ON_ERROR_STOP=1 -q "$@"; }

run_sql < tests/auth_stub.sql
for migration in migrations/*.sql; do
  # pg_cron isn't available in plain Postgres.
  [[ $migration == *_schedule_jobs.sql ]] && continue
  run_sql < "$migration"
done
run_sql < tests/schema_test.sql
