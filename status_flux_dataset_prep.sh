#!/usr/bin/env bash
set -euo pipefail

DATASET_DIR="${1:-/vault/mlperf-flux1-dataset}"

count_files() {
  local dir="$1"
  local pattern="$2"
  find "${dir}" -maxdepth 1 -name "${pattern}" 2>/dev/null | wc -l
}

size_of() {
  local path="$1"
  du -sh "${path}" 2>/dev/null | cut -f1 || true
}

echo "dataset: ${DATASET_DIR}"
df -h "${DATASET_DIR}" 2>/dev/null || true
echo

echo "downloads:"
printf '  cc12m arrows: %s / 4762 (%s)\n' "$(count_files "${DATASET_DIR}/cc12m_preprocessed" '*.arrow')" "$(size_of "${DATASET_DIR}/cc12m_preprocessed")"
printf '  coco arrows:  %s / 129 (%s)\n' "$(count_files "${DATASET_DIR}/coco_preprocessed" '*.arrow')" "$(size_of "${DATASET_DIR}/coco_preprocessed")"
printf '  empty files:  %s / 2 (%s)\n' "$(count_files "${DATASET_DIR}/empty_encodings" '*')" "$(size_of "${DATASET_DIR}/empty_encodings")"
echo

echo "markers:"
for marker in \
  .cc12m_preprocessed.download_complete \
  .coco_preprocessed.download_complete \
  .empty_encodings.download_complete \
  energon/.train_webdataset_complete \
  energon/.val_webdataset_complete \
  energon/.nv-meta/dataset.yaml
do
  if [ -e "${DATASET_DIR}/${marker}" ]; then
    echo "  present: ${marker}"
  else
    echo "  missing: ${marker}"
  fi
done
echo

echo "local dgx processes:"
pgrep -af 'run_flux_dataset_prep|mlperf-flux1-dataset-prep|wget --input-file' || true
echo

if command -v ssh >/dev/null 2>&1; then
  echo "gx10-e313 processes:"
  ssh -o BatchMode=yes -o ConnectTimeout=5 jwm@gx10-e313 \
    "pgrep -af 'flux_dataset_aux|wget --input-file' || true" 2>/dev/null || true
fi
