#!/bin/sh
# Downloads one Geofabrik extract under europe/ into /pbf and checks it.
# Runs in its own build stage per region, so BuildKit fetches them in parallel.
set -eu

region="$1"
url="https://download.geofabrik.de/europe/${region}-latest.osm.pbf"
dest="/pbf/${region}.osm.pbf"

# The checksum first: Geofabrik replaces -latest about once a day, and a new
# file landing between the two requests fails the check below instead of
# passing a mismatched pair. Only a 404 means "no checksum published"; any
# other failure (a timeout, a 429 from 30 stages fetching at once) fails the
# stage, rather than quietly downgrading to the size check.
status="$(curl -sSL --retry 5 --retry-all-errors --retry-delay 10 \
  -o /tmp/extract.md5 -w '%{http_code}' "${url}.md5")" || status="error"
case "${status}" in
  200) md5="$(cut -d' ' -f1 /tmp/extract.md5)" ;;
  404) md5="" ;;
  *) echo "error: ${url}.md5 answered ${status}" >&2; exit 1 ;;
esac

curl -fSL --retry 5 --retry-all-errors --retry-delay 10 -o "${dest}" "${url}"

if [ -n "${md5}" ]; then
  echo "${md5}  ${dest}" | md5sum -c -
else
  # Geofabrik publishes no .md5 for some extracts (germany returned 404 all of
  # 2026-11-06). A size floor still catches a truncated download; the smallest
  # extract here is Malta's, about 10 MB.
  size="$(stat -c%s "${dest}")"
  echo "warning: no checksum published for ${region}; checking size only (${size} bytes)"
  [ "${size}" -gt 5000000 ]
fi
