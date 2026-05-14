#!/usr/bin/env bash
set -euo pipefail

DATASET_DIR="${1:-/vault/mlperf-flux1-dataset}"
IMAGE="${FLUX_DATASET_IMAGE:-mlperf-flux1-dataset-prep:25.09}"
WORKERS="${FLUX_DATASET_WORKERS:-8}"

mkdir -p "${DATASET_DIR}"

docker run --rm -i \
  --user "$(id -u):$(id -g)" \
  --env HOME=/tmp \
  --network=host \
  --ipc=host \
  --volume "${DATASET_DIR}:/dataset" \
  "${IMAGE}" \
  bash -euxo pipefail -c "
    cd /dataset

    if [ ! -f .cc12m_preprocessed.download_complete ]; then
      bash <(curl -fsSL https://raw.githubusercontent.com/mlcommons/r2-downloader/refs/heads/main/mlc-r2-downloader.sh) https://training.mlcommons-storage.org/metadata/flux-1-cc12m-preprocessed.uri
      touch .cc12m_preprocessed.download_complete
    fi

    if [ ! -f .coco_preprocessed.download_complete ]; then
      bash <(curl -fsSL https://raw.githubusercontent.com/mlcommons/r2-downloader/refs/heads/main/mlc-r2-downloader.sh) https://training.mlcommons-storage.org/metadata/flux-1-coco-preprocessed.uri
      touch .coco_preprocessed.download_complete
    fi

    if [ ! -f .empty_encodings.download_complete ]; then
      bash <(curl -fsSL https://raw.githubusercontent.com/mlcommons/r2-downloader/refs/heads/main/mlc-r2-downloader.sh) https://training.mlcommons-storage.org/metadata/flux-1-empty-encodings.uri
      touch .empty_encodings.download_complete
    fi

    mkdir -p energon/train energon/val

    if [ ! -f energon/.train_webdataset_complete ]; then
      python /workspace/flux/scripts/to_webdataset.py --input_path /dataset/cc12m_preprocessed --output_path /dataset/energon/train --num_workers ${WORKERS}
      touch energon/.train_webdataset_complete
    fi

    if [ ! -f energon/.val_webdataset_complete ]; then
      python /workspace/flux/scripts/to_webdataset.py --input_path /dataset/coco_preprocessed --output_path /dataset/energon/val --num_workers ${WORKERS}
      touch energon/.val_webdataset_complete
    fi

    if [ ! -f energon/.nv-meta/dataset.yaml ]; then
      cd energon
      python /workspace/flux/scripts/energon_prepare.py ./ --num-workers ${WORKERS} --template-dir /workspace/flux/scripts/dataset_template/
    fi

    if [ ! -d energon/empty_encodings ]; then
      cp -r empty_encodings energon/
    fi
  "
