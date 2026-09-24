#!/usr/bin/env bash
set -Eeuo pipefail

REGION="${AWS_REGION:-eu-west-2}"
ECR_REPOSITORY="${ECR_REPOSITORY:-cnaim-dev-api}"
ECS_CLUSTER="${ECS_CLUSTER:-cnaim-dev}"
ECS_SERVICE="${ECS_SERVICE:-cnaim-dev-api}"
API_BASE_URL="${API_BASE_URL:-https://cn-e9f6516f75f04a1bbe8597bb64e4d337.ecs.eu-west-2.on.aws}"
IMAGE_TAG="${IMAGE_TAG:-cors-$(git rev-parse --short HEAD 2>/dev/null || date -u +%Y%m%d%H%M%S)}"

for command_name in aws docker curl git; do
  command -v "$command_name" >/dev/null || {
    printf 'Required command not found: %s\n' "$command_name" >&2
    exit 1
  }
done

identity_arn=$(aws sts get-caller-identity --query Arn --output text)
case "$identity_arn" in
  arn:*:root)
    printf 'Refusing to deploy with the AWS root identity.\n' >&2
    exit 1
    ;;
  arn:*:assumed-role/*|arn:*:user/*)
    ;;
  *)
    printf 'Could not verify a non-root AWS identity: %s\n' "$identity_arn" >&2
    exit 1
    ;;
esac

configured_region=$(aws configure get region || true)
if [[ -n "$configured_region" && "$configured_region" != "$REGION" ]]; then
  printf 'Configured AWS region is %s, expected %s. Set AWS_REGION explicitly if intentional.\n' "$configured_region" "$REGION" >&2
  exit 1
fi

account_id=$(aws sts get-caller-identity --query Account --output text)
registry="$account_id.dkr.ecr.$REGION.amazonaws.com"
image_uri="$registry/$ECR_REPOSITORY:$IMAGE_TAG"

printf 'AWS identity: %s\n' "$identity_arn"
printf 'Region: %s\n' "$REGION"
printf 'Image: %s\n' "$image_uri"

aws ecr describe-repositories \
  --repository-names "$ECR_REPOSITORY" \
  --region "$REGION" >/dev/null

aws ecr get-login-password --region "$REGION" |
  docker login --username AWS --password-stdin "$registry" >/dev/null

docker build --tag "$ECR_REPOSITORY:$IMAGE_TAG" .
docker tag "$ECR_REPOSITORY:$IMAGE_TAG" "$image_uri"
docker push "$image_uri"

digest=$(aws ecr describe-images \
  --repository-name "$ECR_REPOSITORY" \
  --image-ids imageTag="$IMAGE_TAG" \
  --region "$REGION" \
  --query 'imageDetails[0].imageDigest' \
  --output text)
printf 'Pushed digest: %s\n' "$digest"

service_arn=$(aws ecs list-services \
  --cluster "$ECS_CLUSTER" \
  --region "$REGION" \
  --query "serviceArns[?contains(@, \`$ECS_SERVICE\`)] | [0]" \
  --output text)
if [[ -z "$service_arn" || "$service_arn" == "None" ]]; then
  printf 'Could not find ECS Express Mode service %s in cluster %s.\n' "$ECS_SERVICE" "$ECS_CLUSTER" >&2
  exit 1
fi

printf 'ECS service: %s\n' "$service_arn"
read -r -p "Update this ECS service to $image_uri? Type deploy to continue: " confirmation
if [[ "$confirmation" != "deploy" ]]; then
  printf 'Deployment cancelled. The image remains in ECR.\n'
  exit 0
fi

aws ecs update-express-gateway-service \
  --service-arn "$service_arn" \
  --primary-container "image=$image_uri" \
  --region "$REGION"

printf '\nService description:\n'
aws ecs describe-express-gateway-service \
  --service-arn "$service_arn" \
  --region "$REGION" \
  --query 'service.{status:status,serviceName:serviceName}' \
  --output table

printf '\nHealth check:\n'
curl --fail --silent --show-error "$API_BASE_URL/health"
printf '\n\nCORS preflight:\n'
curl --fail --silent --show-error --include --request OPTIONS \
  --header 'Origin: https://www.stevenmulvenna.com' \
  --header 'Access-Control-Request-Method: POST' \
  --header 'Access-Control-Request-Headers: content-type' \
  "$API_BASE_URL/api/v1/pof/transformers" |
  awk 'BEGIN { IGNORECASE = 1 } /^HTTP\// || /^access-control-allow-/ || /^vary:/ { print }'

printf '\nDeployment submitted. Continue using synthetic survey data until API authentication and private networking are complete.\n'
