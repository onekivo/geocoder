# KIVO Geocoder

Self-hosted geocoding service based on [open-geocode](https://github.com/open-geocode-rs/open-geocode), with one address pack covering the 27 EU countries plus Norway, Switzerland and the United Kingdom.

Built to power type-ahead address validation and legal address verification in KIVO ([#3767](https://github.com/onekivo/Kivo/issues/3767)).

## Highlights

- **Self-Contained:** One distroless image with the open-geocode binary and the pack. No external database, no Elasticsearch, no JVM.
- **Size (30 countries, 2026-11-07 data):** a 6.35 GB pack of 104.9 M records, which is most of the image (4.2 GB compressed). The pack is memory-mapped, so serving memory grows towards the pack size as queries touch it.
- **Build:** about 2 h 15 min on a 4-core, 16 GB GitHub runner, the pack 2 h 4 min of it. Peak build memory 9 GB, while writing records, with a 6 GB buffer budget.
- **Typo-Tolerant:** Automatic Levenshtein typo correction and accent normalization (e.g. `Chaussestraße 111` finds `Chausseestraße 111`; `Gran Via` matches `Gran Vía`).
- **Monthly Updates:** Automatically rebuilt on the 15th of each month at 03:00 UTC from fresh [Geofabrik](https://download.geofabrik.de/) OpenStreetMap extracts. GitHub disables a public repository's schedules after 60 days without activity; if a month passes with no new `data-` tag, re-enable the workflow under Actions.

## Quick Start

```bash
docker run -d --name geocoder -p 8080:8080 ghcr.io/onekivo/geocoder:latest
```

Check health:

```bash
curl http://localhost:8080/readyz
```

Search an address:

```bash
curl "http://localhost:8080/search?q=Chaussestra%C3%9Fe+111,+10115+Berlin&limit=1"
```

## Docker Compose

```yaml
services:
  geocoder:
    image: ghcr.io/onekivo/geocoder:latest
    restart: unless-stopped
    ports:
      - "8080:8080"
    healthcheck:
      test: ["CMD", "open-geocode", "health"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 20s
```

## API Reference

The container exposes open-geocode's HTTP API on port `8080`:

| Endpoint | Method | Purpose | Notes |
|---|---|---|---|
| `/search` | `GET` | Address search & resolution | Full query string with house number, street, city and/or postcode. Handles typos and accents. |
| `/autocomplete` | `GET` | Prefix search | Suitable for street-name autocompletion before a house number is entered. |
| `/reverse` | `GET` | Reverse geocoding | `lat` and `lon` query parameters. Returns nearest address and admin boundary. |
| `/readyz` | `GET` | Readiness probe | Returns `200 OK` when the pack is mapped and ready to serve queries. |
| `/healthz` | `GET` | Liveness probe | Returns `200 OK` if the process is responsive. |

### Accuracy Tiers

Every feature returned by `/search` includes `properties.accuracy`:

- `rooftop`: Address exists at an exact building/cadastral point in the map data.
- `interpolated`: Address estimated along a numbered street way (flag as unconfirmed if strict cadastral match is required).
- `street`: Street match without verified house number.
- `place` / `centroid`: Locality, district, or administrative area fallback.

## Build

Everything happens inside `docker build`:

1. `builder` compiles `open-geocode` at `OPEN_GEOCODE_REF`.
2. One `pbf-<country>` stage per extract downloads it from Geofabrik and checks its published MD5 (`scripts/fetch-extract.sh`). BuildKit runs them in parallel.
3. `pack` bind-mounts every extract and builds the pack; its scratch files and the build's `audit/` folder (every skipped OSM object, 2.9 GB for ten countries) are deleted in the same `RUN`, so the stage keeps only the pack. `open-geocode pack verify` checks it, and the build report is printed into the build log.
4. The distroless runtime copies the binary and the pack. No extract or scratch file reaches the final image.

```bash
docker build --build-arg OSM_DATE=$(date -u +%F) -t geocoder:local .
docker run -d -p 8080:8080 geocoder:local
```

`OSM_DATE` invalidates the download layers; without a new value Docker reuses the extracts it already has.

To add a country: add a `pbf-<country>` stage with its Geofabrik name under `europe/`, a `--mount` line in the `pack` stage, and a smoke-test query in `.github/workflows/build.yml`. The United Kingdom is `great-britain` plus `ireland-and-northern-ireland`; Geofabrik's `united-kingdom` would include Northern Ireland twice.

## Data Attribution & License

- **Engine:** [open-geocode](https://github.com/open-geocode-rs/open-geocode) by open-geocode contributors, licensed under the MIT License.
- **Map Data:** OpenStreetMap data © [OpenStreetMap contributors](https://www.openstreetmap.org/copyright), licensed under the [Open Database License (ODbL)](https://opendatacommons.org/licenses/odbl/).
- **Repository:** MIT License.
