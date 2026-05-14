#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATASET_DIR="${DATASET_DIR:-/vault/mlperf-flux1-dataset}"
LOG_DIR="${LOG_DIR:-${ROOT_DIR}/logs}"
CONCURRENCY_DEFAULT="${CONCURRENCY_DEFAULT:-10}"
RESTART=0
GENERATE=0

usage() {
  cat <<'EOF'
Usage: ./start_cc12m_sidecars.sh [--generate] [--restart] [node...]

Starts MLCommons R2 aria2 sidecars for cc12m_preprocessed on configured nodes.

Options:
  --generate   Regenerate URL slice files before starting sidecars.
  --restart    Stop any matching sidecar on the target node before starting.

Nodes:
  dgx gx10-e313 astra nebula orbital
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --generate)
      GENERATE=1
      shift
      ;;
    --restart)
      RESTART=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    -*)
      echo "unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
    *)
      break
      ;;
  esac
done

mkdir -p "${LOG_DIR}"

if [ "${GENERATE}" = "1" ]; then
  "${ROOT_DIR}/generate_cc12m_sidecar_slices.sh"
fi

sidecar_spec() {
  case "$1" in
    dgx)
      echo "local|cc12m_dgx_2601_2764|${CONCURRENCY_DEFAULT}"
      ;;
    gx10-e313)
      echo "ssh|cc12m_tail_2000|${CONCURRENCY_DEFAULT}"
      ;;
    astra)
      echo "ssh|cc12m_astra_0501_1200|${CONCURRENCY_DEFAULT}"
      ;;
    nebula)
      echo "ssh|cc12m_nebula_1201_1900|${CONCURRENCY_DEFAULT}"
      ;;
    orbital)
      echo "ssh|cc12m_orbital_1901_2600|${CONCURRENCY_DEFAULT}"
      ;;
    *)
      return 1
      ;;
  esac
}

start_command() {
  local name="$1"
  local concurrency="$2"
  local urls="${LOG_DIR}/${name}.urls"
  local log="${LOG_DIR}/${name}.aria2.log"
  local pidfile="${LOG_DIR}/${name}.pid"
  local dataset_subdir="${DATASET_DIR}/cc12m_preprocessed"

  cat <<EOF
set -euo pipefail
mkdir -p '${LOG_DIR}' '${dataset_subdir}'
if ! command -v aria2c >/dev/null 2>&1; then
  echo 'aria2c is required on this node' >&2
  exit 1
fi
if [ ! -f '${urls}' ]; then
  echo 'missing URL slice: ${urls}' >&2
  exit 1
fi
if [ -f '${pidfile}' ] && kill -0 "\$(cat '${pidfile}')" 2>/dev/null; then
  if [ '${RESTART}' = '1' ]; then
    kill "\$(cat '${pidfile}')" || true
    sleep 1
  else
    echo '${name} already running pid='"\$(cat '${pidfile}')"
    exit 0
  fi
fi
printf '\n== %s starting ${name} max-concurrent-downloads=${concurrency} ==\n' "\$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> '${log}'
setsid aria2c \
  --input-file='${urls}' \
  --dir='${dataset_subdir}' \
  --continue=true \
  --auto-file-renaming=false \
  --allow-overwrite=false \
  --conditional-get=true \
  --file-allocation=none \
  --max-concurrent-downloads='${concurrency}' \
  --max-connection-per-server=4 \
  --split=4 \
  --min-split-size=16M \
  --retry-wait=5 \
  --max-tries=0 \
  --summary-interval=60 \
  --console-log-level=notice \
  >> '${log}' 2>&1 < /dev/null &
echo \$! > '${pidfile}'
echo '${name} started pid='"\$!"
EOF
}

start_node() {
  local node="$1"
  local spec
  local mode
  local name
  local concurrency

  spec="$(sidecar_spec "${node}")" || {
    echo "unknown node: ${node}" >&2
    return 1
  }
  IFS='|' read -r mode name concurrency <<<"${spec}"

  case "${mode}" in
    local)
      bash -lc "$(start_command "${name}" "${concurrency}")"
      ;;
    ssh)
      # The generated command intentionally expands local paths before SSH.
      # shellcheck disable=SC2029
      ssh "jwm@${node}" "$(start_command "${name}" "${concurrency}")"
      ;;
    *)
      echo "unknown sidecar mode for ${node}: ${mode}" >&2
      return 1
      ;;
  esac
}

if [ "$#" -eq 0 ]; then
  set -- dgx gx10-e313 astra nebula orbital
fi

for node in "$@"; do
  start_node "${node}"
done
