#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${LOG_DIR:-${ROOT_DIR}/logs}"

mkdir -p "${LOG_DIR}"

generate_slice() {
  local name="$1"
  local start_line="$2"
  local end_line="$3"
  local output="${LOG_DIR}/${name}.urls"

  uv run "${ROOT_DIR}/tools/make_cc12m_aria2_urls.py" \
    --arrow-only \
    --start-line "${start_line}" \
    --end-line "${end_line}" \
    --output "${output}"
}

generate_slice cc12m_astra_0501_1200 501 1200
generate_slice cc12m_nebula_1201_1900 1201 1900
generate_slice cc12m_orbital_1901_2600 1901 2600
generate_slice cc12m_dgx_2601_2764 2601 2764
generate_slice cc12m_tail_2000 2765 4762

wc -l \
  "${LOG_DIR}/cc12m_astra_0501_1200.urls" \
  "${LOG_DIR}/cc12m_nebula_1201_1900.urls" \
  "${LOG_DIR}/cc12m_orbital_1901_2600.urls" \
  "${LOG_DIR}/cc12m_dgx_2601_2764.urls" \
  "${LOG_DIR}/cc12m_tail_2000.urls"
