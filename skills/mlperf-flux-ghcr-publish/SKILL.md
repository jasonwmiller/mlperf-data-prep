---
name: mlperf-flux-ghcr-publish
description: Use when publishing the MLPerf FLUX dataset-prep Docker image from the DGX Spark nodes to GHCR under ghcr.io/jasonwmiller/mlperf-data-prep/flux-dataset-prep, including checking GitHub package scopes, avoiding token leaks, tagging, pushing, and documenting image state.
---

# MLPerf FLUX GHCR Publish

Use this skill to publish the dataset-prep image from a Spark node. Do not add
GitHub Actions image builds for this project.

## Context

- Local image: `mlperf-flux1-dataset-prep:25.09`
- GHCR image: `ghcr.io/jasonwmiller/mlperf-data-prep/flux-dataset-prep`
- Published tags by default:
  `ghcr.io/jasonwmiller/mlperf-data-prep/flux-dataset-prep:25.09` and
  `ghcr.io/jasonwmiller/mlperf-data-prep/flux-dataset-prep:latest`
- Publish script: `/vault/mlperf-data-prep/publish_flux_dataset_image.sh`
- Required auth scope: `write:packages`

## Workflow

1. Verify repository state:

```bash
cd /vault/mlperf-data-prep
git status --short --branch
docker image inspect mlperf-flux1-dataset-prep:25.09 --format '{{.Id}} {{.Size}} {{.Architecture}}/{{.Os}}'
```

2. Verify GitHub CLI scopes and refresh if needed:

```bash
gh auth status
gh auth refresh -h github.com -s write:packages
```

3. Publish the existing local image:

```bash
cd /vault/mlperf-data-prep
SKIP_BUILD=1 ./publish_flux_dataset_image.sh 25.09
```

4. Or rebuild then publish:

```bash
cd /vault/mlperf-data-prep
./publish_flux_dataset_image.sh 25.09
```

5. Confirm package visibility or pull access after push:

```bash
docker pull ghcr.io/jasonwmiller/mlperf-data-prep/flux-dataset-prep:25.09
docker pull ghcr.io/jasonwmiller/mlperf-data-prep/flux-dataset-prep:latest
```

Only the prep image is published. Do not publish dataset files or WebDataset
shards to GHCR.

## Secret Handling

- Never write actual token values to files or commits.
- Use `GHCR_TOKEN` only as an environment variable when needed.
- `gh auth token` may be piped to `docker login`, but do not echo it.
- Before committing publish/auth changes, scan:

```bash
rg -n --hidden --no-ignore-vcs \
  -g '!.git/**' -g '!logs/**' -g '!training_results_v5.1/**' \
  '(gho_[A-Za-z0-9_]+|ghp_[A-Za-z0-9_]+|github_pat_[A-Za-z0-9_]+|GHCR_TOKEN=[^[:space:]]+|CF_ACCESS_CLIENT_SECRET=[^[:space:]]+|cf-access-token: [A-Za-z0-9_.-]+|Authorization:|BEGIN [A-Z ]*PRIVATE KEY)' .
```

## Failure Notes

- `denied: permission_denied: The token provided does not match expected scopes`
  means the active token lacks `write:packages`; refresh with host specified.
- Docker may warn that credentials are stored unencrypted in
  `/home/jwm/.docker/config.json`; that file is outside this repo and must not
  be copied into the project.
