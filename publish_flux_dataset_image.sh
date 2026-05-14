#!/usr/bin/env bash
set -euo pipefail

TAG="${1:-25.09}"
IMAGE="${GHCR_IMAGE:-ghcr.io/jasonwmiller/mlperf-data-prep/flux-dataset-prep}"
LOCAL_IMAGE="${LOCAL_IMAGE:-mlperf-flux1-dataset-prep:${TAG}}"
PUSH_LATEST="${PUSH_LATEST:-1}"
SKIP_BUILD="${SKIP_BUILD:-0}"
GHCR_USER="${GHCR_USER:-jasonwmiller}"

cd "$(dirname "${BASH_SOURCE[0]}")"

if [ "${SKIP_BUILD}" != "1" ]; then
  docker build \
    -f Dockerfile.flux-dataset-prep \
    -t "${LOCAL_IMAGE}" \
    .
fi

if [ -n "${GHCR_TOKEN:-}" ]; then
  printf '%s' "${GHCR_TOKEN}" | docker login ghcr.io -u "${GHCR_USER}" --password-stdin
elif command -v gh >/dev/null 2>&1; then
  gh auth token | docker login ghcr.io -u "${GHCR_USER}" --password-stdin
else
  echo "Set GHCR_TOKEN to a token with write:packages, or install/authenticate gh." >&2
  exit 1
fi

docker tag "${LOCAL_IMAGE}" "${IMAGE}:${TAG}"
docker push "${IMAGE}:${TAG}"

if [ "${PUSH_LATEST}" = "1" ]; then
  docker tag "${LOCAL_IMAGE}" "${IMAGE}:latest"
  docker push "${IMAGE}:latest"
fi
