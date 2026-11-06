# syntax=docker/dockerfile:1

# The open-geocode commit to build. CI passes the newest one whose CI passed
# on open-geocode's main; the default is the last one this repo verified.
ARG OPEN_GEOCODE_REF=08813468f8fbe491e6533e9c5101e56da5e9b29e

# --- open-geocode binary ------------------------------------------------------
# Debian 13 like the runtime, so the glibc it links against matches.
FROM rust:1.99.1-slim-trixie@sha256:7eab7ce19273ce785e0ca7578bdf7bc1fcbae621775a8197379a04c9f6e03cd5 AS builder
ARG OPEN_GEOCODE_REF
RUN apt-get update && apt-get install -y --no-install-recommends git ca-certificates \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /src
RUN git clone https://github.com/open-geocode-rs/open-geocode.git . \
 && git checkout "${OPEN_GEOCODE_REF}" \
 && cargo build --release --locked --bin open-geocode \
 && strip target/release/open-geocode

# --- OpenStreetMap extracts, one stage per region -------------------------------
# Separate stages so BuildKit downloads them in parallel. Nothing here reaches
# the final image: the pack stage only bind-mounts them.
FROM curlimages/curl:8.17.0@sha256:935d9100e9ba842cdb060de42472c7ca90cfe9a7c96e4dacb55e79e560b3ff40 AS fetch
USER root
# A new value re-downloads every extract; CI passes the build date, so a
# cached layer never serves last week's map.
ARG OSM_DATE=unset
ENV OSM_DATE=${OSM_DATE}
COPY scripts/fetch-extract.sh /usr/local/bin/fetch-extract
RUN mkdir /pbf

FROM fetch AS pbf-germany
RUN fetch-extract germany
FROM fetch AS pbf-spain
RUN fetch-extract spain
FROM fetch AS pbf-austria
RUN fetch-extract austria
FROM fetch AS pbf-switzerland
RUN fetch-extract switzerland
FROM fetch AS pbf-france
RUN fetch-extract france
FROM fetch AS pbf-belgium
RUN fetch-extract belgium
FROM fetch AS pbf-netherlands
RUN fetch-extract netherlands
FROM fetch AS pbf-luxembourg
RUN fetch-extract luxembourg
# England, Scotland and Wales. Northern Ireland comes with Ireland below;
# Geofabrik's united-kingdom would carry it twice.
FROM fetch AS pbf-great-britain
RUN fetch-extract great-britain
FROM fetch AS pbf-ireland
RUN fetch-extract ireland-and-northern-ireland

# --- The pack -------------------------------------------------------------------
# Reads every extract through a bind mount and keeps its scratch inside the same
# RUN, so this stage's only layer is the finished pack. `pack build` also writes
# an audit/ folder next to the pack: every OSM object it skipped (2.9 GB for ten
# countries) and a build report. `serve` never reads it, so the RUN prints the
# report into the build log and deletes the folder.
FROM debian:trixie-slim@sha256:a72b4433de1cf7d6bae0c4cee74d0547f58601a643b3375f070c51600d63b6b2 AS pack
ARG PACK_MEMORY_MB=8192
COPY --from=builder /src/target/release/open-geocode /usr/local/bin/open-geocode
RUN --mount=type=bind,from=pbf-germany,source=/pbf,target=/in/de \
    --mount=type=bind,from=pbf-spain,source=/pbf,target=/in/es \
    --mount=type=bind,from=pbf-austria,source=/pbf,target=/in/at \
    --mount=type=bind,from=pbf-switzerland,source=/pbf,target=/in/ch \
    --mount=type=bind,from=pbf-france,source=/pbf,target=/in/fr \
    --mount=type=bind,from=pbf-belgium,source=/pbf,target=/in/be \
    --mount=type=bind,from=pbf-netherlands,source=/pbf,target=/in/nl \
    --mount=type=bind,from=pbf-luxembourg,source=/pbf,target=/in/lu \
    --mount=type=bind,from=pbf-great-britain,source=/pbf,target=/in/gb \
    --mount=type=bind,from=pbf-ireland,source=/pbf,target=/in/ie \
    set -eu; \
    inputs=""; \
    for f in /in/*/*.osm.pbf; do inputs="${inputs} --input ${f}"; done; \
    open-geocode pack build ${inputs} \
      --pack /packs/pack \
      --scratch-dir /scratch \
      --memory-budget-mb "${PACK_MEMORY_MB}"; \
    rm -rf /scratch; \
    open-geocode pack verify --pack /packs/pack; \
    cat /packs/pack/generations/*/audit/build-report.json | head -c 2000; echo; \
    rm -rf /packs/pack/generations/*/audit

# --- Runtime --------------------------------------------------------------------
# Distroless cc: glibc, libgcc and CA certificates only. No shell, no package
# manager, uid 65532.
FROM gcr.io/distroless/cc-debian13:nonroot@sha256:08476c244888bfb425bae1ae4dd7c17f093e972aab8426883d97f3c6f280f7c1
LABEL org.opencontainers.image.title="KIVO Geocoder" \
      org.opencontainers.image.description="Self-hosted geocoder for Germany, Spain, Austria, Switzerland, France, Belgium, the Netherlands, Luxembourg, the United Kingdom and Ireland, based on open-geocode" \
      org.opencontainers.image.licenses="MIT AND ODbL-1.0"
COPY --from=builder /src/target/release/open-geocode /usr/local/bin/open-geocode
COPY --from=pack --chown=nonroot:nonroot /packs/pack /packs/pack
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s CMD ["open-geocode", "health"]
ENTRYPOINT ["open-geocode"]
CMD ["serve", "--pack", "/packs/pack", "--bind", "0.0.0.0:8080"]
