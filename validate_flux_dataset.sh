#!/usr/bin/env bash
set -euo pipefail

DATASET_DIR="${1:-/vault/mlperf-flux1-dataset}"

required_paths=(
  "${DATASET_DIR}/energon/train"
  "${DATASET_DIR}/energon/val"
  "${DATASET_DIR}/energon/empty_encodings"
  "${DATASET_DIR}/energon/.nv-meta/dataset.yaml"
)

for path in "${required_paths[@]}"; do
  if [ ! -e "${path}" ]; then
    echo "missing: ${path}" >&2
    exit 1
  fi
done

train_shards="$(find "${DATASET_DIR}/energon/train" -maxdepth 1 -name 'shard_*.tar' | wc -l)"
val_shards="$(find "${DATASET_DIR}/energon/val" -maxdepth 1 -name 'shard_*.tar' | wc -l)"

if [ "${train_shards}" -eq 0 ] || [ "${val_shards}" -eq 0 ]; then
  echo "missing webdataset shards: train=${train_shards} val=${val_shards}" >&2
  exit 1
fi

echo "dataset: ${DATASET_DIR}"
echo "train shards: ${train_shards}"
echo "val shards: ${val_shards}"
du -sh "${DATASET_DIR}/energon"
