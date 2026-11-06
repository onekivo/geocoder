# KIVO Geocoder

Self-hosted geocoding service based on [open-geocode](https://github.com/open-geocode-rs/open-geocode), pre-packaged with unified address packs for Germany (`DE`) and Spain (`ES`).

Built to power type-ahead address validation and legal address verification in KIVO ([#3767](https://github.com/onekivo/Kivo/issues/3767)).

## Highlights

- **Lightweight & Self-Contained:** Single distroless image (~1.6 GB) containing both the pure-Rust runtime and the compiled binary index. No external database, no Elasticsearch, no JVM.
- **Low Overhead:** Single memory-mapped index (~1.54 GB) with ~1.5 GB RSS while serving.
- **Typo-Tolerant:** Automatic Levenshtein typo correction and accent normalization (e.g. `Chaussestraße 111` finds `Chausseestraße 111`; `Gran Via` matches `Gran Vía`).
- **Weekly Updates:** Automatically rebuilt every Sunday at 03:00 UTC from fresh [Geofabrik](https://download.geofabrik.de/) OpenStreetMap extracts.

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

## Local Build

To build the pack and container image locally:

```bash
# 1. Download extracts and build pack (requires open-geocode binary or cargo)
bash scripts/build-pack.sh

# 2. Build the Docker image
docker build -t geocoder:local .

# 3. Run
docker run -d -p 8080:8080 geocoder:local
```

## Data Attribution & License

- **Engine:** [open-geocode](https://github.com/open-geocode-rs/open-geocode) by open-geocode contributors, licensed under the MIT License.
- **Map Data:** OpenStreetMap data © [OpenStreetMap contributors](https://www.openstreetmap.org/copyright), licensed under the [Open Database License (ODbL)](https://opendatacommons.org/licenses/odbl/).
- **Repository:** MIT License.
