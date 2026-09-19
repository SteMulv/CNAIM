#!/usr/bin/env bash
set -euo pipefail

image="${1:-cnaim-pof-api:fixed}"
port="${2:-8002}"
container_name="cnaim-pof-api-test"
base_url="http://127.0.0.1:${port}"
response_file="$(mktemp)"
log_file="$(mktemp)"

cleanup() {
  docker rm -f "$container_name" >/dev/null 2>&1 || true
  rm -f "$response_file" "$log_file"
}
trap cleanup EXIT

echo "Building $image"
docker build --no-cache -t "$image" .

echo "Verifying packages inside the image"
docker run --rm --entrypoint R "$image" -q -e \
  'stopifnot(requireNamespace("plumber", quietly=TRUE), requireNamespace("CNAIM", quietly=TRUE)); cat("Docker packages verified\n")'

echo "Starting container on port $port"
docker run -d --name "$container_name" -p "$port:8000" "$image" >/dev/null

for attempt in {1..60}; do
  if curl -fsS "$base_url/health" >"$response_file" 2>/dev/null; then
    break
  fi
  if [[ "$attempt" == 60 ]]; then
    docker logs "$container_name"
    echo "Docker API did not start" >&2
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
  --data '{"schema_version":"1.0","asset_id":"DockerLogCheck","asset_type":"6.6/11kV Transformer (GM)","survey":{"age":25}}' \
  >"$response_file"
grep -q '"pof"' "$response_file"
grep -q '"chs"' "$response_file"

status=$(curl -sS -o "$response_file" -w '%{http_code}' \
  -X POST "$base_url/api/v1/pof/transformers" \
  -H 'Content-Type: application/json' \
  --data '{"schema_version":"1.0","asset_id":"DockerLogCheck","asset_type":"6.6/11kV Transformer (GM)","function":"system","survey":{"age":25}}')
[[ "$status" == "400" ]]
grep -q '"code":"UNSUPPORTED_FIELD"' "$response_file"

docker stop "$container_name" >/dev/null
docker logs "$container_name" >"$log_file" 2>&1
grep -q '"method":"GET"' "$log_file"
grep -q '"path":"/health"' "$log_file"
grep -q '"status":200' "$log_file"
grep -q '"method":"POST"' "$log_file"
grep -q '"error_code":"UNSUPPORTED_FIELD"' "$log_file"
! grep -q 'DockerLogCheck' "$log_file"
! grep -q '"function"' "$log_file"

echo "Docker API and structured logging tests passed"
