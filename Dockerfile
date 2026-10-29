# syntax=docker/dockerfile:1

# jevos-v5 OpenVINO INT8 decision engine, CPU only.
# Upstream: https://github.com/feder-cr/jev/releases
ARG JEV_VERSION=jevos-v5

# --- fetch: download the exact release assets and verify bytes -----------------
FROM alpine:3.20 AS fetch
ARG JEV_VERSION
# Hashes from the release's SHA256SUMS.txt. A version bump MUST come with new
# hashes or the build fails on purpose (fail-closed supply chain).
ARG BINARY_SHA256=1ce77566405514ed2f20d64f8222cf9eba9b714d332f05f6296e0cad84dd7b04
ARG MODEL_SHA256=0a1159c31b9c2abc484af9c866cdcfe5279fdf592b368636625c5a795f970acc

RUN apk add --no-cache curl unzip
WORKDIR /src
RUN set -eux; \
    base="https://github.com/feder-cr/jev/releases/download/${JEV_VERSION}"; \
    curl -fsSL --retry 3 --retry-delay 2 -o jev.tar.gz "$base/jev-linux-x64.tar.gz"; \
    curl -fsSL --retry 3 --retry-delay 2 -o model.zip "$base/${JEV_VERSION}-openvino-int8.zip"; \
    printf '%s  jev.tar.gz\n%s  model.zip\n' "$BINARY_SHA256" "$MODEL_SHA256" > sums; \
    sha256sum -c sums; \
    tar -xzf jev.tar.gz; \
    unzip -q model.zip -d jev; \
    rm -f jev.tar.gz model.zip; \
    test -f jev/model/model.json

# --- runtime: glibc 2.36 (binary needs >= 2.35), no build tools ---------------
FROM debian:bookworm-slim
ARG JEV_VERSION
LABEL org.opencontainers.image.title="jevos" \
      org.opencontainers.image.version="${JEV_VERSION}" \
      org.opencontainers.image.source="https://github.com/feder-cr/jev"

RUN apt-get update \
 && apt-get install -y --no-install-recommends curl \
 && rm -rf /var/lib/apt/lists/* \
 && useradd --system --uid 10001 --home-dir /opt/jev --shell /usr/sbin/nologin jev

COPY --from=fetch --chown=10001:10001 /src/jev /opt/jev
COPY --chmod=0755 --chown=10001:10001 entrypoint.sh /usr/local/bin/entrypoint.sh
WORKDIR /opt/jev
USER 10001:10001

# THREADS: number of inference threads. Set it to the container's CPU quota —
# the binary otherwise counts host CPUs and oversubscribes a limited container.
ENV PORT=8017
EXPOSE 8017

HEALTHCHECK --interval=30s --timeout=3s --start-period=60s --retries=3 \
  CMD curl -fsS "http://127.0.0.1:${PORT}/health" || exit 1

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
