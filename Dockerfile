# syntax=docker/dockerfile:1

# Stage 1: Build the open-geocode binary using Debian 13 (matching runtime glibc)
FROM rust:1.99.1-slim-trixie@sha256:7eab7ce19273ce785e0ca7578bdf7bc1fcbae621775a8197379a04c9f6e03cd5 AS builder

ARG OPEN_GEOCODE_REPO=https://github.com/open-geocode-rs/open-geocode.git
ARG OPEN_GEOCODE_REF=08813468f8fbe491e6533e9c5101e56da5e9b29e

RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    ca-certificates \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /src
RUN git clone "${OPEN_GEOCODE_REPO}" . \
 && git checkout "${OPEN_GEOCODE_REF}" \
 && cargo build --release --locked --bin open-geocode \
 && strip target/release/open-geocode

# Stage 2: Minimal runtime image
# Distroless cc: glibc, libgcc and CA certificates only. No shell, no package manager, uid 65532.
FROM gcr.io/distroless/cc-debian13:nonroot@sha256:08476c244888bfb425bae1ae4dd7c17f093e972aab8426883d97f3c6f280f7c1

# Copy the binary from the builder stage
COPY --from=builder /src/target/release/open-geocode /usr/local/bin/open-geocode

# Copy the pre-built Germany + Spain pack
COPY --chown=nonroot:nonroot pack /packs/de-es

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=30s CMD ["open-geocode", "health"]

ENTRYPOINT ["open-geocode"]
CMD ["serve", "--pack", "/packs/de-es", "--bind", "0.0.0.0:8080"]
