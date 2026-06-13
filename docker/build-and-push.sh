#!/usr/bin/env bash
# Build the SWAT+ worker base image and push it to ECR as staRburst's base image
# for the client R version (GAP A workaround).
#
# WHY THIS SHAPE: staRburst does NOT run a prebuilt image directly. Its
# ensure_environment() builds a *new* env image FROM starburst-worker:base-<Rver>
# (+ renv::restore() + worker.R) and selects the base purely by R version. So the
# only way to get the SWAT+ binary onto a worker is to make THIS image BE the
# base-<Rver> tag staRburst looks for. We therefore build a strict SUPERSET of
# staRburst's stock base (same apt + R deps) plus the SWAT+ ifx binary, and push
# it over the base-<Rver> tag.
#
# This is the documented GAP-A friction: there is no per-workload base, so we
# overwrite the shared base-<Rver> tag. The stock base is trivially regenerable
# (staRburst rebuilds it on demand), and we retag the prior image as a backup
# first, so this is reversible.
#
# MULTI-ARCH: staRburst's env build is hardcoded to --platform
# linux/amd64,linux/arm64, so the base MUST be a multi-arch manifest or that
# build fails resolving the arm64 base. The SWAT+ binary is x86_64/ifx and is
# never executed at build time (it only runs on the amd64 c7i.xlarge worker), so
# it rides along harmlessly on the never-run arm64 variant.
#
# Usage: R_VERSION=4.6.0 docker/build-and-push.sh [region]
set -euo pipefail

REGION="${1:-us-east-1}"
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
REPO="starburst-worker"
R_VERSION="${R_VERSION:-4.6.0}"          # MUST match the staRburst client's R
TAG="base-${R_VERSION}"                  # the exact tag staRburst resolves
REGISTRY="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"
URI="${REGISTRY}/${REPO}:${TAG}"

echo ">>> Target: ${URI} (multi-platform amd64+arm64)"
echo ">>> This OVERWRITES the shared ${TAG} tag (GAP-A workaround)."

aws ecr get-login-password --region "${REGION}" \
  | docker login --username AWS --password-stdin "${REGISTRY}"

# Backup the existing base-<Rver> so the clobber is reversible.
if aws ecr describe-images --repository-name "${REPO}" --region "${REGION}" \
     --image-ids imageTag="${TAG}" >/dev/null 2>&1; then
  echo ">>> Backing up existing ${TAG} -> ${TAG}-stock-backup"
  MANIFEST="$(aws ecr batch-get-image --repository-name "${REPO}" --region "${REGION}" \
                --image-ids imageTag="${TAG}" --query 'images[0].imageManifest' --output text)"
  aws ecr put-image --repository-name "${REPO}" --region "${REGION}" \
    --image-tag "${TAG}-stock-backup" --image-manifest "${MANIFEST}" >/dev/null 2>&1 \
    || echo "    (backup tag already exists — skipping)"
fi

# Need a buildx builder that can emit both arches. starburst-builder (created by
# staRburst) is multi-arch capable; fall back to creating one.
docker buildx use starburst-builder 2>/dev/null \
  || docker buildx create --name swatdemo --driver docker-container --bootstrap --use

docker buildx build \
  --platform linux/amd64,linux/arm64 \
  --build-arg "R_VERSION=${R_VERSION}" \
  -t "${URI}" \
  --push \
  "$(dirname "$0")"

cat <<EOF

Pushed: ${URI}

staRburst will now use this as the worker base for R ${R_VERSION}: its env layer
(renv::restore + worker.R) builds FROM this image, so the SWAT+ binary survives.

To restore the stock base later, retag the backup over ${TAG}:
  M=\$(aws ecr batch-get-image --repository-name ${REPO} --region ${REGION} \\
        --image-ids imageTag=${TAG}-stock-backup --query 'images[0].imageManifest' --output text)
  aws ecr put-image --repository-name ${REPO} --region ${REGION} \\
    --image-tag ${TAG} --image-manifest "\$M"
EOF
