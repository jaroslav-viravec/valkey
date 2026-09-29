# =============================================================================
# Valkey — built from valkey.io SOURCE (Bitnami-free)
#
# Issue #2030 / EPIC #740: our own Valkey image, compiled from source — NOT from
# any Bitnami tarball and NOT FROM the docker.io/bitnami/* or valkey/valkey
# images.
#
# This Dockerfile compiles the source tree that is passed as the BUILD CONTEXT.
# It lives in this fork (jaroslav-viravec/valkey); the build context is either:
#   - a pinned release tag's source (the CI workflow checks out tag 9.1.2), or
#   - this repo checkout itself (local build via scripts/build-valkey-docker.sh).
#
#   docker build -f docker/Dockerfile -t valkey:9.1.2 <path-to-valkey-source>
#
# The resulting image ships all Valkey binaries, so it serves BOTH roles:
#   - valkey-server   (primary/replica)
#   - valkey-sentinel (run `valkey-sentinel /path/to/sentinel.conf`)
# =============================================================================

# Runtime + build base. Debian 12 (bookworm) matches the chart's "-debian-12".
ARG BASE_IMAGE=debian:bookworm-slim
# Informational only (image label / tag). The code actually compiled is whatever
# is in the build context; CI passes the pinned release version here.
ARG VALKEY_VERSION=9.1.2

# =============================================================================
# Stage 1: build — compile the Valkey source tree from the build context
# =============================================================================
FROM ${BASE_IMAGE} AS build

# Build toolchain. g++ is required for USE_FAST_FLOAT=yes (Valkey 8.1+).
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        dpkg-dev \
        gcc \
        g++ \
        libc6-dev \
        libssl-dev \
        make \
        pkg-config; \
    rm -rf /var/lib/apt/lists/*

WORKDIR /usr/src/valkey

# Copy the source tree (the build context) and compile it.
COPY . .

# Compile with TLS support and install into a self-contained prefix.
# BUILD_TLS=yes      -> valkey-server/-cli/-sentinel support TLS
# USE_FAST_FLOAT=yes -> faster float parsing (Valkey 8.1+, needs g++)
RUN set -eux; \
    make distclean >/dev/null 2>&1 || true; \
    make -j "$(nproc)" \
        BUILD_TLS=yes \
        USE_FAST_FLOAT=yes \
        all; \
    make install PREFIX=/opt/valkey; \
    /opt/valkey/bin/valkey-server --version; \
    strip /opt/valkey/bin/valkey-*

# =============================================================================
# Stage 2: runtime — minimal image with just the binaries + a non-root user
# =============================================================================
FROM ${BASE_IMAGE} AS runtime
ARG VALKEY_VERSION

LABEL org.opencontainers.image.title="valkey" \
      org.opencontainers.image.description="Valkey built from valkey.io source (Bitnami-free)" \
      org.opencontainers.image.version="${VALKEY_VERSION}" \
      org.opencontainers.image.source="https://github.com/jaroslav-viravec/valkey" \
      org.opencontainers.image.licenses="BSD-3-Clause"

# Runtime deps only: TLS libs + a minimal init (tini) for correct signal/zombie
# handling as PID 1.
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        libssl3 \
        tini \
        tzdata; \
    rm -rf /var/lib/apt/lists/*

# Copy the compiled binaries from the build stage.
COPY --from=build /opt/valkey /opt/valkey
ENV PATH="/opt/valkey/bin:${PATH}"

# Non-root user. UID/GID 1001 and group-0 permissions so the image also works
# under Kubernetes/OpenShift "arbitrary UID" (runAsUser injected by the chart).
RUN set -eux; \
    groupadd --gid 1001 valkey; \
    useradd  --uid 1001 --gid 1001 --system --home-dir /data --shell /usr/sbin/nologin valkey; \
    mkdir -p /data /opt/valkey/etc; \
    chown -R 1001:0 /data /opt/valkey/etc; \
    chmod -R g=u /data /opt/valkey/etc

# Entrypoint (generated inline; keeps the Dockerfile self-contained so it builds
# from any source context without an extra file to COPY). Normalizes args the
# way the official image does:
#   - a leading flag  ("-...")  -> prepend valkey-server
#   - a bare ".conf" file       -> prepend valkey-server
#   - anything else runs verbatim, e.g. `valkey-sentinel /path/sentinel.conf`
RUN set -eux; \
    { \
        echo '#!/bin/sh'; \
        echo 'set -e'; \
        echo 'if [ "${1#-}" != "$1" ]; then set -- valkey-server "$@"; fi'; \
        echo 'case "$1" in'; \
        echo '  *.conf) set -- valkey-server "$@" ;;'; \
        echo 'esac'; \
        echo 'exec "$@"'; \
    } > /usr/local/bin/docker-entrypoint.sh; \
    chmod +x /usr/local/bin/docker-entrypoint.sh

WORKDIR /data
VOLUME ["/data"]

# 6379 = valkey-server, 26379 = valkey-sentinel
EXPOSE 6379 26379

USER 1001

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/docker-entrypoint.sh"]
CMD ["valkey-server"]
