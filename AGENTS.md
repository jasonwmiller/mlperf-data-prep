# Agent Guidance

This repository manages MLPerf Training v5.1 NVIDIA FLUX dataset preparation on
the two-node DGX Spark cluster.

## Environment

- Primary node: `dgx`
- Secondary node: `gx10-e313`
- Secondary SSH: `ssh jwm@gx10-e313`
- Shared mount: `/vault`
- NFS source: `172.27.1.170:/vault/nfs`
- Project path: `/vault/mlperf-data-prep`
- Dataset path: `/vault/mlperf-flux1-dataset`
- Public repo: `https://github.com/jasonwmiller/mlperf-data-prep`
- GHCR image: `ghcr.io/jasonwmiller/mlperf-data-prep/flux-dataset-prep`

## Local Skills

Use these repo-local skills when a task matches their description:

- `skills/mlperf-flux-dataset-prep/SKILL.md`: mount validation, source checkout,
  image build, dataset download/preprocess, status, resume, and final validation.
- `skills/mlperf-flux-ghcr-publish/SKILL.md`: publishing the dataset-prep image
  to GHCR from a Spark node.

## Operating Rules

- Keep large generated data out of git. The dataset, logs, sparse upstream
  checkout, Docker layers, and WebDataset shards are intentionally ignored.
- Do not commit credentials, tokens, Docker auth config, GitHub auth config, or
  logs that might contain secrets.
- Pre-commit is configured with `detect-secrets` and `shellcheck`. The
  `detect-secrets` wrapper uses `uv run` with PEP 723 inline metadata. Run
  checks before committing:

```bash
pre-commit run --all-files
```

Refresh the secret baseline after intentional scanner/config changes:

```bash
uv run tools/detect_secrets.py update
```

- Before commits involving publishing or auth changes, scan for token-like
  strings:

```bash
rg -n --hidden --no-ignore-vcs \
  -g '!.git/**' -g '!logs/**' -g '!training_results_v5.1/**' \
  '(gho_[A-Za-z0-9_]+|ghp_[A-Za-z0-9_]+|github_pat_[A-Za-z0-9_]+|GHCR_TOKEN=[^[:space:]]+|CF_ACCESS_CLIENT_SECRET=[^[:space:]]+|cf-access-token: [A-Za-z0-9_.-]+|Authorization:|BEGIN [A-Z ]*PRIVATE KEY)' .
```

- Prefer the checked-in wrapper scripts over retyping long commands.
- Dataset downloads are resumable. Do not delete partial dataset directories
  unless the user explicitly asks to start over.
- `cc12m_preprocessed` should come from MLCommons R2 metadata. The official URI
  is `https://training.mlcommons-storage.org/metadata/flux-1-cc12m-preprocessed.uri`;
  the matching MD5 list is in `mlcommons/r2-infra`. Use
  `uv run tools/make_cc12m_aria2_urls.py` for aria2 sidecar URL slices.
- The image is built and published from Spark nodes, not by GitHub Actions.
- Use `apply_patch` for repository edits.

## Common Commands

Build image:

```bash
docker build -f Dockerfile.flux-dataset-prep -t mlperf-flux1-dataset-prep:25.09 .
```

Run dataset prep:

```bash
setsid env FLUX_DATASET_WORKERS=8 \
  /vault/mlperf-data-prep/run_flux_dataset_prep.sh /vault/mlperf-flux1-dataset \
  > /vault/mlperf-data-prep/logs/flux_dataset_prep.log 2>&1 < /dev/null &
echo $! > /vault/mlperf-data-prep/logs/flux_dataset_prep.pid
```

Check status:

```bash
/vault/mlperf-data-prep/status_flux_dataset_prep.sh /vault/mlperf-flux1-dataset
```

Generate a second-half R2 URL slice for `aria2c` on `gx10-e313`:

```bash
uv run /vault/mlperf-data-prep/tools/make_cc12m_aria2_urls.py \
  --arrow-only \
  --partitions 2 \
  --partition-index 2 \
  --output /vault/mlperf-data-prep/logs/cc12m_r2_part2.urls
```

Publish existing local image:

```bash
SKIP_BUILD=1 /vault/mlperf-data-prep/publish_flux_dataset_image.sh 25.09
```
