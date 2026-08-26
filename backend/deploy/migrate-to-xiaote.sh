#!/usr/bin/env bash
set -euo pipefail

old_dir=/opt/tesla-backend/deploy
new_dir=/opt/xiaote-backend/deploy
migration_complete=false

rollback() {
  if [[ "$migration_complete" == false ]]; then
    echo "Migration failed; restoring the previous service." >&2
    cd "$new_dir"
    docker compose down >/dev/null 2>&1 || true
    cd "$old_dir"
    docker compose up -d
  fi
}
trap rollback ERR

cd "$old_dir"
docker compose down

for volume in backend_data command_cache caddy_data caddy_config; do
  old_volume="tesla-backend_${volume}"
  new_volume="xiaote-backend_${volume}"
  docker volume create "$new_volume" >/dev/null
  docker run --rm \
    --volume "$old_volume:/source:ro" \
    --volume "$new_volume:/target" \
    caddy:2-alpine sh -c 'cp -a /source/. /target/'
done

cd "$new_dir"
docker compose up -d

for _ in $(seq 1 20); do
  if curl --fail --silent https://api.txx.app/health | grep -q '"service":"xiaote-backend"'; then
    migration_complete=true
    trap - ERR
    echo "Xiaote backend migration completed."
    docker ps --format '{{.Names}} {{.Status}}'
    exit 0
  fi
  sleep 2
done

echo "Xiaote backend did not become healthy in time." >&2
exit 1
