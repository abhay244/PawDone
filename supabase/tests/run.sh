#!/usr/bin/env bash
# Runs the migrations and every *_test.sql file against a throwaway Postgres in Docker.
# Each test file gets its own fresh database.
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

for test in tests/*_test.sql; do
  database=$(basename "$test" .sql)
  run_sql -c "create database $database"
  run_sql -d "$database" < tests/auth_stub.sql
  for migration in migrations/*.sql; do
    # pg_cron, pg_net and Vault aren't available in plain Postgres.
    [[ $migration == *_schedule_*.sql ]] && continue
    run_sql -d "$database" < "$migration"
  done
  run_sql -d "$database" < tests/helpers.sql
  echo "== $test"
  run_sql -d "$database" < "$test"
done
