#!/usr/bin/env bash
set -euo pipefail

PBF_DIR="${PBF_DIR:-pbf}"
PACK_DIR="${PACK_DIR:-pack}"
MEMORY_BUDGET_MB="${MEMORY_BUDGET_MB:-8192}"
OPEN_GEOCODE_BIN="${OPEN_GEOCODE_BIN:-open-geocode}"

mkdir -p "${PBF_DIR}" "${PACK_DIR}"

download_pbf() {
  local region="$1"
  local url="https://download.geofabrik.de/europe/${region}-latest.osm.pbf"
  local dest="${PBF_DIR}/${region}.osm.pbf"

  if [ -s "${dest}" ]; then
    echo "Using existing ${dest} ($(du -h "${dest}" | cut -f1))"
    return 0
  fi

  echo "Downloading ${region} extract from ${url}..."
  curl -fSL --retry 5 --retry-delay 3 -C - -o "${dest}" "${url}"
  echo "Downloaded ${dest} ($(du -h "${dest}" | cut -f1))"
}

download_pbf "germany"
download_pbf "spain"

# Guard against truncated downloads (< 500 MB)
for r in germany spain; do
  size_bytes=$(stat -c%s "${PBF_DIR}/${r}.osm.pbf" 2>/dev/null || stat -f%z "${PBF_DIR}/${r}.osm.pbf")
  if [ "${size_bytes}" -lt 524288000 ]; then
    echo "Error: ${PBF_DIR}/${r}.osm.pbf is suspiciously small (${size_bytes} bytes). Deleting."
    rm -f "${PBF_DIR}/${r}.osm.pbf"
    exit 1
  fi
done
echo "Building combined DE+ES pack in ${PACK_DIR} (memory budget: ${MEMORY_BUDGET_MB} MiB)..."
rm -rf "${PACK_DIR}"

"${OPEN_GEOCODE_BIN}" pack build \
  --input "${PBF_DIR}/germany.osm.pbf" \
  --input "${PBF_DIR}/spain.osm.pbf" \
  --pack "${PACK_DIR}" \
  --memory-budget-mb "${MEMORY_BUDGET_MB}"

echo "Pack build complete: $(du -sh "${PACK_DIR}" | cut -f1)"
