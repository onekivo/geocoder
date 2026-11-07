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
FROM fetch AS pbf-italy
RUN fetch-extract italy
FROM fetch AS pbf-poland
RUN fetch-extract poland
FROM fetch AS pbf-portugal
RUN fetch-extract portugal
FROM fetch AS pbf-czech-republic
RUN fetch-extract czech-republic
FROM fetch AS pbf-slovakia
RUN fetch-extract slovakia
FROM fetch AS pbf-hungary
RUN fetch-extract hungary
FROM fetch AS pbf-slovenia
RUN fetch-extract slovenia
FROM fetch AS pbf-croatia
RUN fetch-extract croatia
FROM fetch AS pbf-romania
RUN fetch-extract romania
FROM fetch AS pbf-bulgaria
RUN fetch-extract bulgaria
FROM fetch AS pbf-greece
RUN fetch-extract greece
FROM fetch AS pbf-cyprus
RUN fetch-extract cyprus
FROM fetch AS pbf-malta
RUN fetch-extract malta
FROM fetch AS pbf-denmark
RUN fetch-extract denmark
FROM fetch AS pbf-sweden
RUN fetch-extract sweden
FROM fetch AS pbf-norway
RUN fetch-extract norway
FROM fetch AS pbf-finland
RUN fetch-extract finland
FROM fetch AS pbf-estonia
RUN fetch-extract estonia
FROM fetch AS pbf-latvia
RUN fetch-extract latvia
FROM fetch AS pbf-lithuania
RUN fetch-extract lithuania

# --- The pack -------------------------------------------------------------------
# Reads every extract through a bind mount and keeps its scratch inside the same
# RUN, so this stage's only layer is the finished pack. `pack build` also writes
# an audit/ folder next to the pack: every OSM object it skipped (2.9 GB for ten
# countries) and a build report. `serve` never reads it, so the RUN prints the
# report into the build log and deletes the folder.
FROM debian:trixie-slim@sha256:a72b4433de1cf7d6bae0c4cee74d0547f58601a643b3375f070c51600d63b6b2 AS pack
# Buffers only; the build's own index of objects comes on top (7.3 GB peak for
# ten countries with 8192). The runner has 16 GB, so past this budget the build
# spills to scratch on disk instead.
ARG PACK_MEMORY_MB=6144
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
    --mount=type=bind,from=pbf-italy,source=/pbf,target=/in/it \
    --mount=type=bind,from=pbf-poland,source=/pbf,target=/in/pl \
    --mount=type=bind,from=pbf-portugal,source=/pbf,target=/in/pt \
    --mount=type=bind,from=pbf-czech-republic,source=/pbf,target=/in/cz \
    --mount=type=bind,from=pbf-slovakia,source=/pbf,target=/in/sk \
    --mount=type=bind,from=pbf-hungary,source=/pbf,target=/in/hu \
    --mount=type=bind,from=pbf-slovenia,source=/pbf,target=/in/si \
    --mount=type=bind,from=pbf-croatia,source=/pbf,target=/in/hr \
    --mount=type=bind,from=pbf-romania,source=/pbf,target=/in/ro \
    --mount=type=bind,from=pbf-bulgaria,source=/pbf,target=/in/bg \
    --mount=type=bind,from=pbf-greece,source=/pbf,target=/in/gr \
    --mount=type=bind,from=pbf-cyprus,source=/pbf,target=/in/cy \
    --mount=type=bind,from=pbf-malta,source=/pbf,target=/in/mt \
    --mount=type=bind,from=pbf-denmark,source=/pbf,target=/in/dk \
    --mount=type=bind,from=pbf-sweden,source=/pbf,target=/in/se \
    --mount=type=bind,from=pbf-norway,source=/pbf,target=/in/no \
    --mount=type=bind,from=pbf-finland,source=/pbf,target=/in/fi \
    --mount=type=bind,from=pbf-estonia,source=/pbf,target=/in/ee \
    --mount=type=bind,from=pbf-latvia,source=/pbf,target=/in/lv \
    --mount=type=bind,from=pbf-lithuania,source=/pbf,target=/in/lt \
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
      org.opencontainers.image.description="Self-hosted geocoder for the European Union, Norway, Switzerland and the United Kingdom, based on open-geocode" \
      org.opencontainers.image.licenses="MIT AND ODbL-1.0"
COPY --from=builder /src/target/release/open-geocode /usr/local/bin/open-geocode
COPY --from=pack --chown=nonroot:nonroot /packs/pack /packs/pack
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s CMD ["open-geocode", "health"]
ENTRYPOINT ["open-geocode"]
CMD ["serve", "--pack", "/packs/pack", "--bind", "0.0.0.0:8080"]
