#!/usr/bin/env bash
# Build the SWAT+ worker base image and push it to your ECR so staRburst can
# use it as the private base (GAP A). Multi-platform to match staRburst workers.
#
# Usage: docker/build-and-push.sh [region]
set -euo pipefail

REGION="${1:-us-east-1}"
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
REPO="starburst-worker"               # staRburst's repo; we publish a base-* tag
R_VERSION="${R_VERSION:-4.4.2}"
TAG="base-swatplus-${R_VERSION}"
URI="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${REPO}:${TAG}"

echo "Building ${URI} (multi-platform)…"
aws ecr get-login-password --region "${REGION}" \
  | docker login --username AWS --password-stdin \
      "${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"

docker buildx create --name swatdemo --driver docker-container --bootstrap --use 2>/dev/null || \
  docker buildx use swatdemo

docker buildx build \
  --builder swatdemo \
  --platform linux/amd64,linux/arm64 \
  --build-arg "BASE_IMAGE=rocker/r-ver:${R_VERSION}" \
  -t "${URI}" \
  --push \
  "$(dirname "$0")"

cat <<EOF

Pushed: ${URI}

Next: point staRburst at this base image. Either set use_public_base = FALSE in
starburst_setup() (it will look for a base-<rversion> tag in this repo), or wire
the tag '${TAG}' into your setup. See scripts/01-setup.R.
EOF
