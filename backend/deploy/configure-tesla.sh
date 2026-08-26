#!/usr/bin/env bash
set -euo pipefail

env_file=/opt/tesla-backend/secrets/backend.env
compose_dir=/opt/tesla-backend/deploy
auth_url=https://auth.tesla.cn/oauth2/v3/token
fleet_url=https://fleet-api.prd.cn.vn.cloud.tesla.cn
app_domain=api.txx.app

if [[ ! -f "$env_file" ]]; then
  echo "Missing $env_file" >&2
  exit 1
fi

read -r -p "Tesla Client ID: " client_id
read -r -s -p "Tesla Client Secret: " client_secret
printf '\n'

if [[ -z "$client_id" || -z "$client_secret" ]]; then
  echo "Client ID and Client Secret are required." >&2
  exit 1
fi

encryption_key="$(sed -n 's/^TOKEN_ENCRYPTION_KEY=//p' "$env_file")"
if [[ -z "$encryption_key" ]]; then
  echo "TOKEN_ENCRYPTION_KEY is missing." >&2
  exit 1
fi

tmp_file="$(mktemp)"
trap 'rm -f "$tmp_file"; unset client_secret partner_token' EXIT
umask 077
printf '%s\n' \
  "TESLA_CLIENT_ID=$client_id" \
  "TESLA_CLIENT_SECRET=$client_secret" \
  "TOKEN_ENCRYPTION_KEY=$encryption_key" \
  'PUBLIC_URL=https://api.txx.app' \
  'APP_CALLBACK_URL=teslablekey://oauth/callback' \
  'TESLA_AUTH_BASE_URL=https://auth.tesla.cn/oauth2/v3' \
  'TESLA_FLEET_BASE_URL=https://fleet-api.prd.cn.vn.cloud.tesla.cn' \
  'TESLA_COMMAND_PROXY_URL=https://vehicle-command:4443' \
  'TESLA_COMMAND_PROXY_CA=/secrets/proxy-ca.pem' > "$tmp_file"
install -m 600 "$tmp_file" "$env_file"

cd "$compose_dir"
docker compose up -d --force-recreate backend gateway

partner_response="$(curl --fail-with-body --silent --show-error \
  --request POST \
  --header 'Content-Type: application/x-www-form-urlencoded' \
  --data-urlencode 'grant_type=client_credentials' \
  --data-urlencode "client_id=$client_id" \
  --data-urlencode "client_secret=$client_secret" \
  --data-urlencode 'scope=openid vehicle_device_data vehicle_cmds vehicle_charging_cmds' \
  --data-urlencode "audience=$fleet_url" \
  "$auth_url")"
partner_token="$(jq -r '.access_token // empty' <<<"$partner_response")"
if [[ -z "$partner_token" ]]; then
  echo "Tesla did not return a partner access token." >&2
  exit 1
fi

register_file="$(mktemp)"
register_status="$(curl --silent --show-error \
  --output "$register_file" \
  --write-out '%{http_code}' \
  --request POST \
  --header 'Content-Type: application/json' \
  --header "Authorization: Bearer $partner_token" \
  --data "{\"domain\":\"$app_domain\"}" \
  "$fleet_url/api/1/partner_accounts")"

if [[ "$register_status" != "200" && "$register_status" != "201" && "$register_status" != "409" ]]; then
  echo "Partner registration failed with HTTP $register_status:" >&2
  jq -c 'del(.access_token, .refresh_token)' "$register_file" 2>/dev/null || true
  rm -f "$register_file"
  exit 1
fi
rm -f "$register_file"

public_key_status="$(curl --silent --output /dev/null --write-out '%{http_code}' \
  --header 'Range: bytes=0-200' \
  "https://$app_domain/.well-known/appspecific/com.tesla.3p.public-key.pem")"

echo "Tesla OAuth configured."
echo "Partner registration HTTP: $register_status"
echo "Hosted public key HTTP: $public_key_status"
echo "Health: https://api.txx.app/health"
