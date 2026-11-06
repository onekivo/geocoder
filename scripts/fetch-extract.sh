#!/bin/sh
# Downloads one Geofabrik extract under europe/ into /pbf and checks it.
# Runs in its own build stage per region, so BuildKit fetches them in parallel.
set -eu

region="$1"
url="https://download.geofabrik.de/europe/${region}-latest.osm.pbf"
dest="/pbf/${region}.osm.pbf"

# The checksum first: Geofabrik replaces -latest about once a day, and a new
# file landing between the two requests fails the check below instead of
# passing a mismatched pair.
md5=""
if curl -fsSL --retry 5 --retry-all-errors -o /tmp/extract.md5 "${url}.md5"; then
  md5="$(cut -d' ' -f1 /tmp/extract.md5)"
fi

curl -fSL --retry 5 --retry-all-errors -o "${dest}" "${url}"

if [ -n "${md5}" ]; then
  echo "${md5}  ${dest}" | md5sum -c -
else
  # Geofabrik publishes no .md5 for some extracts (germany returned 404 all of
  # 2026-11-06). A size floor still catches a truncated download; a real
  # extract is at least Luxembourg's ~50 MB.
  size="$(stat -c%s "${dest}")"
  echo "warning: no checksum published for ${region}; checking size only (${size} bytes)"
  [ "${size}" -gt 20000000 ]
fi
