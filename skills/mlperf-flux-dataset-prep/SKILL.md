---
name: mlperf-flux-dataset-prep
description: Use for MLPerf Training v5.1 NVIDIA FLUX dataset operations on this DGX Spark cluster, including validating the /vault NFS mount, preparing the sparse upstream checkout, building the dataset-prep Docker image, starting or resuming downloads and preprocessing, monitoring progress, and validating final Energon/WebDataset output.
---

# MLPerf FLUX Dataset Prep

Use this skill for dataset setup and operation in `/vault/mlperf-data-prep`.

## Context

- Primary node: `dgx`
- Secondary node: `gx10-e313`
- Shared mount: `/vault`
- NFS source: `172.27.1.170:/vault/nfs`
- Dataset path: `/vault/mlperf-flux1-dataset`
- Prep image: `mlperf-flux1-dataset-prep:25.09`
- Upstream instructions: `https://github.com/mlcommons/training_results_v5.1/tree/main/NVIDIA/benchmarks/flux1/implementations/tyche_ngpu16_ngc25.09_nemo#32-download-dataset-and-preprocess`

## Workflow

1. Check repo and mount state:

```bash
cd /vault/mlperf-data-prep
git status --short --branch
findmnt /vault
df -h /vault /vault/mlperf-flux1-dataset 2>/dev/null || true
ssh -o BatchMode=yes -o ConnectTimeout=5 jwm@gx10-e313 'findmnt /vault; df -h /vault'
```

2. Recreate the sparse upstream checkout only if missing:

```bash
cd /vault/mlperf-data-prep
git clone --filter=blob:none --no-checkout https://github.com/mlcommons/training_results_v5.1.git training_results_v5.1
cd training_results_v5.1
git sparse-checkout init --cone
git sparse-checkout set NVIDIA/benchmarks/flux1/implementations/tyche_ngpu16_ngc25.09_nemo
git checkout main
```

3. Build the dataset-prep image when needed:

```bash
cd /vault/mlperf-data-prep
docker build -f Dockerfile.flux-dataset-prep -t mlperf-flux1-dataset-prep:25.09 .
```

4. Start or resume the main job on `dgx`:

```bash
mkdir -p /vault/mlperf-data-prep/logs /vault/mlperf-flux1-dataset
setsid env FLUX_DATASET_WORKERS=8 \
  /vault/mlperf-data-prep/run_flux_dataset_prep.sh /vault/mlperf-flux1-dataset \
  >> /vault/mlperf-data-prep/logs/flux_dataset_prep.log 2>&1 < /dev/null &
echo $! > /vault/mlperf-data-prep/logs/flux_dataset_prep.pid
```

5. Optionally run small auxiliary downloads on `gx10-e313`, only when those
   marker files are still missing:

```bash
ssh jwm@gx10-e313 '
  mkdir -p /vault/mlperf-data-prep/logs /vault/mlperf-flux1-dataset
  setsid bash -lc '"'"'
    set -euo pipefail
    cd /vault/mlperf-flux1-dataset
    if [ ! -f .coco_preprocessed.download_complete ]; then
      bash <(curl -fsSL https://raw.githubusercontent.com/mlcommons/r2-downloader/refs/heads/main/mlc-r2-downloader.sh) https://training.mlcommons-storage.org/metadata/flux-1-coco-preprocessed.uri
      touch .coco_preprocessed.download_complete
    fi
    if [ ! -f .empty_encodings.download_complete ]; then
      bash <(curl -fsSL https://raw.githubusercontent.com/mlcommons/r2-downloader/refs/heads/main/mlc-r2-downloader.sh) https://training.mlcommons-storage.org/metadata/flux-1-empty-encodings.uri
      touch .empty_encodings.download_complete
    fi
  '"'"' > /vault/mlperf-data-prep/logs/flux_dataset_aux_downloads.gx10.log 2>&1 < /dev/null &
  echo $! > /vault/mlperf-data-prep/logs/flux_dataset_aux_downloads.gx10.pid
'
```

6. Monitor with the checked-in helper:

```bash
/vault/mlperf-data-prep/status_flux_dataset_prep.sh /vault/mlperf-flux1-dataset
tail -f /vault/mlperf-data-prep/logs/flux_dataset_prep.log
```

7. Validate only after preprocessing completes:

```bash
/vault/mlperf-data-prep/validate_flux_dataset.sh /vault/mlperf-flux1-dataset
```

## Rules

- Do not delete partial downloads unless the user explicitly asks to start over.
- The MLCommons downloader uses `wget --continue`; reruns resume.
- Completion marker files are authoritative for wrapper stages:
  `.cc12m_preprocessed.download_complete`,
  `.coco_preprocessed.download_complete`,
  `.empty_encodings.download_complete`,
  `energon/.train_webdataset_complete`,
  `energon/.val_webdataset_complete`.
- Keep `logs/`, `training_results_v5.1/`, and dataset directories out of git.
- If editing scripts, run `bash -n` on changed shell scripts before committing.
