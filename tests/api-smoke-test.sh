#!/usr/bin/env bash
set -euo pipefail

port="${1:-8001}"
base_url="http://127.0.0.1:${port}"
response_file="$(mktemp)"

cleanup() {
  if [[ -n "${api_pid:-}" ]]; then
    kill "$api_pid" 2>/dev/null || true
    wait "$api_pid" 2>/dev/null || true
  fi
  rm -f "$response_file"
}
trap cleanup EXIT

R -q -e "pr <- plumber::plumb('plumber.R'); pr\$run(host='127.0.0.1', port=${port})" >/tmp/cnaim-api-test.log 2>&1 &
api_pid=$!

for attempt in {1..30}; do
  if curl -fsS "$base_url/health" >"$response_file" 2>/dev/null; then
    break
  fi
  if [[ "$attempt" == 30 ]]; then
    cat /tmp/cnaim-api-test.log
    echo "API did not start" >&2
    exit 1
  fi
  sleep 1
done

grep -q '"status":"ok"' "$response_file"
curl -fsS "$base_url/version" >"$response_file"
grep -q '"api_schema_version":"1.0"' "$response_file"
grep -q '"engine":"CNAIM"' "$response_file"

curl -fsS -X POST "$base_url/api/v1/pof/transformers" \
  -H 'Content-Type: application/json' \
  --data '{"schema_version":"1.0","asset_id":"Transformer_11kV_400V_001","asset_type":"6.6/11kV Transformer (GM)","survey":{"age":25}}' \
  >"$response_file"
grep -q '"pof"' "$response_file"
grep -q '"chs"' "$response_file"

status=$(curl -sS -o "$response_file" -w '%{http_code}' \
  -X POST "$base_url/api/v1/pof/transformers" \
  -H 'Content-Type: application/json' \
  --data '{"schema_version":"1.0","asset_id":"Transformer_11kV_400V_001","asset_type":"6.6/11kV Transformer (GM)","function":"system","survey":{"age":25}}')
[[ "$status" == "400" ]]
grep -q '"code":"UNSUPPORTED_FIELD"' "$response_file"

echo "API smoke tests passed"
