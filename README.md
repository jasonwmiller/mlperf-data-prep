# MLPerf FLUX Dataset Prep

This project prepares the MLPerf Training v5.1 NVIDIA FLUX dataset for the
two-node DGX Spark cluster.

Public repo:

```text
https://github.com/jasonwmiller/mlperf-data-prep
```

The workflow follows NVIDIA's MLPerf FLUX dataset instructions:

https://github.com/mlcommons/training_results_v5.1/tree/main/NVIDIA/benchmarks/flux1/implementations/tyche_ngpu16_ngc25.09_nemo#32-download-dataset-and-preprocess

## Cluster Layout

- Primary node: `dgx`
- Secondary node: `gx10-e313`
- Secondary SSH: `ssh jwm@gx10-e313`
- Shared dataset mount: `/vault`
- NFS source: `172.27.1.170:/vault/nfs`
- Dataset target: `/vault/mlperf-flux1-dataset`
- Prep project: `/vault/mlperf-data-prep`

Both nodes have Docker installed. The dataset does not need GPUs for download
or preprocessing, but the scripts use NVIDIA's `nvcr.io/nvidia/pytorch:25.09-py3`
container as the base runtime.

## NFS Mount

The `/vault` mount has been validated on both nodes with NFSv4.2:

```bash
sudo mkdir -p /vault
sudo mount -t nfs -o vers=4.2,proto=tcp 172.27.1.170:/vault/nfs /vault
findmnt /vault
df -h /vault
```

Persistent `/etc/fstab` entry:

```fstab
172.27.1.170:/vault/nfs /vault nfs4 vers=4.2,proto=tcp,rsize=1048576,wsize=1048576,_netdev,nofail,noauto,x-systemd.automount 0 0
```

## Source Checkout

The MLPerf Training v5.1 repository is checked out sparsely under:

```bash
/vault/mlperf-data-prep/training_results_v5.1
```

Only the NVIDIA FLUX implementation subtree is needed:

```bash
NVIDIA/benchmarks/flux1/implementations/tyche_ngpu16_ngc25.09_nemo
```

If the checkout needs to be recreated:

```bash
cd /vault/mlperf-data-prep
git clone --filter=blob:none --no-checkout https://github.com/mlcommons/training_results_v5.1.git training_results_v5.1
cd training_results_v5.1
git sparse-checkout init --cone
git sparse-checkout set NVIDIA/benchmarks/flux1/implementations/tyche_ngpu16_ngc25.09_nemo
git checkout main
```

## Build The Prep Image

Build the lightweight dataset-prep image on `dgx`:

```bash
cd /vault/mlperf-data-prep
docker build -f Dockerfile.flux-dataset-prep -t mlperf-flux1-dataset-prep:25.09 .
```

The image is built and published from a Spark node, not by GitHub Actions:

```bash
cd /vault/mlperf-data-prep
./publish_flux_dataset_image.sh 25.09
```

To publish the already-built local image without rebuilding:

```bash
cd /vault/mlperf-data-prep
SKIP_BUILD=1 ./publish_flux_dataset_image.sh 25.09
```

The published image name is:

```bash
ghcr.io/jasonwmiller/mlperf-data-prep/flux-dataset-prep:25.09
```

Published GHCR tags:

- `ghcr.io/jasonwmiller/mlperf-data-prep/flux-dataset-prep:25.09`
- `ghcr.io/jasonwmiller/mlperf-data-prep/flux-dataset-prep:latest`

The `latest` tag is pushed by default. Set `PUSH_LATEST=0` to publish only the
explicit version tag. These are Linux ARM64 images built for the Spark nodes.
The MLPerf dataset itself is not published to GHCR.

Publishing requires a GitHub token with `write:packages`. Either export
`GHCR_TOKEN` or authenticate `gh` with that scope before running the script:

```bash
gh auth refresh -h github.com -s write:packages
```

The publish script logs in to GHCR using `GHCR_TOKEN` when set, otherwise it
uses `gh auth token`.

The image installs:

- `datasets`
- `megatron-energon==7.1.0`
- MLPerf logging/common requirements
- `rapidyaml==0.9.0` built from source for ARM/aarch64

## Run Dataset Prep

Start the main download and preprocessing flow on `dgx`:

```bash
mkdir -p /vault/mlperf-data-prep/logs /vault/mlperf-flux1-dataset
setsid env FLUX_DATASET_WORKERS=8 \
  /vault/mlperf-data-prep/run_flux_dataset_prep.sh /vault/mlperf-flux1-dataset \
  > /vault/mlperf-data-prep/logs/flux_dataset_prep.log 2>&1 < /dev/null &
echo $! > /vault/mlperf-data-prep/logs/flux_dataset_prep.pid
```

The wrapper downloads:

- `cc12m_preprocessed`
- `coco_preprocessed`
- `empty_encodings`

Then it converts `cc12m` and `coco` to WebDataset/Energon format under:

```bash
/vault/mlperf-flux1-dataset/energon
```

## Two-Node Download Assist

The large `cc12m_preprocessed` download runs on `dgx`. The smaller `coco` and
`empty_encodings` downloads can run on `gx10-e313` at the same time:

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

The main `dgx` wrapper uses completion marker files, so it skips completed
download stages when resumed.

## Status

Check progress:

```bash
/vault/mlperf-data-prep/status_flux_dataset_prep.sh /vault/mlperf-flux1-dataset
```

Watch logs:

```bash
tail -f /vault/mlperf-data-prep/logs/flux_dataset_prep.log
ssh jwm@gx10-e313 'tail -f /vault/mlperf-data-prep/logs/flux_dataset_aux_downloads.gx10.log'
```

Expected raw download counts:

- `cc12m_preprocessed`: 4,762 `.arrow` files
- `coco_preprocessed`: 129 `.arrow` files
- `empty_encodings`: 2 `.npy` files

The MLCommons downloader also writes checksum files and validates MD5 sums.

## Resume Or Restart

The MLCommons downloader uses `wget --continue`, so interrupted downloads can
resume. To restart the `dgx` job:

```bash
kill "$(cat /vault/mlperf-data-prep/logs/flux_dataset_prep.pid)" 2>/dev/null || true
docker ps --filter ancestor=mlperf-flux1-dataset-prep:25.09 --format '{{.ID}}' | xargs -r docker stop

setsid env FLUX_DATASET_WORKERS=8 \
  /vault/mlperf-data-prep/run_flux_dataset_prep.sh /vault/mlperf-flux1-dataset \
  >> /vault/mlperf-data-prep/logs/flux_dataset_prep.log 2>&1 < /dev/null &
echo $! > /vault/mlperf-data-prep/logs/flux_dataset_prep.pid
```

Do not delete partially downloaded dataset directories unless intentionally
starting over.

## Validate

After preprocessing completes:

```bash
/vault/mlperf-data-prep/validate_flux_dataset.sh /vault/mlperf-flux1-dataset
```

The validator checks that:

- `energon/train` exists and contains train shards
- `energon/val` exists and contains validation shards
- `energon/empty_encodings` exists
- `energon/.nv-meta/dataset.yaml` exists

## Important Paths

- Project README: `/vault/mlperf-data-prep/README.md`
- Prep Dockerfile: `/vault/mlperf-data-prep/Dockerfile.flux-dataset-prep`
- Main wrapper: `/vault/mlperf-data-prep/run_flux_dataset_prep.sh`
- Status helper: `/vault/mlperf-data-prep/status_flux_dataset_prep.sh`
- Final validator: `/vault/mlperf-data-prep/validate_flux_dataset.sh`
- Main log: `/vault/mlperf-data-prep/logs/flux_dataset_prep.log`
- Aux log: `/vault/mlperf-data-prep/logs/flux_dataset_aux_downloads.gx10.log`
- Dataset: `/vault/mlperf-flux1-dataset`

## Development Checks

Install hooks:

```bash
cd /vault/mlperf-data-prep
pre-commit install
```

Run all checks:

```bash
pre-commit run --all-files
```

The secret scanner is invoked through `uv run tools/detect_secrets.py`, which
uses PEP 723 inline dependency metadata. Refresh the baseline only after
intentional scanner/config changes:

```bash
uv run tools/detect_secrets.py update
```
