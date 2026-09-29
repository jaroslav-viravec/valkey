#!/usr/bin/env bash
#
# build-valkey-docker.sh — build our Bitnami-free Valkey image from source.
#
# Lives inside the valkey fork (jaroslav-viravec/valkey). Compiles a Valkey
# source tree with docker/Dockerfile. No tarball download — a source tree is the
# Docker build context.
#
# By default it builds THIS repo checkout (the parent dir of scripts/). Note the
# `issue2030` branch is based on `unstable`, so its src/version.h is the dev
# marker 255.255.255. To build a pinned release locally, either check out the
# tag first (`git checkout 9.1.2`) or pass TAG=9.1.2 SOURCE_DIR=<tag-worktree>.
# For reproducible pinned images, prefer the CI workflow (.github/workflows/
# build-valkey-image.yaml), which builds a release tag's source.
#
# Usage:
#   scripts/build-valkey-docker.sh                    # build this checkout
#   SOURCE_DIR=/path/to/valkey-9.1.2 scripts/build-valkey-docker.sh
#   IMAGE=ghcr.io/jaroslav-viravec/valkey TAG=9.1.2 scripts/build-valkey-docker.sh
#
# Env overrides:
#   SOURCE_DIR  path to the Valkey source tree (default: this repo root)
#   IMAGE       image repo name        (default: valkey)
#   TAG         image tag              (default: version read from source)
#   BASE_IMAGE  runtime/build base     (default: Dockerfile default)
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
DOCKERFILE="${REPO_DIR}/docker/Dockerfile"

# Default: build this repo checkout.
SOURCE_DIR="${SOURCE_DIR:-${REPO_DIR}}"

log() { printf '\033[1;34m==>\033[0m %s\n' "$*" >&2; }
die() { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

command -v docker >/dev/null || die "docker not found on PATH"
[ -f "${DOCKERFILE}" ]               || die "Dockerfile not found: ${DOCKERFILE}"
[ -d "${SOURCE_DIR}" ]               || die "source dir not found: ${SOURCE_DIR}"
[ -f "${SOURCE_DIR}/src/version.h" ] || die "not a Valkey source tree (no src/version.h): ${SOURCE_DIR}"

# Read the real version straight from the source we are about to compile.
VERSION="$(sed -nE 's/^#define VALKEY_VERSION "([^"]+)".*/\1/p' "${SOURCE_DIR}/src/version.h")"
[ -n "${VERSION}" ] || die "could not read VALKEY_VERSION from ${SOURCE_DIR}/src/version.h"
log "Source tree: ${SOURCE_DIR} (Valkey ${VERSION})"
[ "${VERSION}" = "255.255.255" ] && \
    log "note: 255.255.255 is the dev marker (unstable branch). Set TAG= or check out a release tag for a pinned image."

IMAGE="${IMAGE:-valkey}"
TAG="${TAG:-${VERSION}}"
FULL="${IMAGE}:${TAG}"

BUILD_ARGS=( --build-arg "VALKEY_VERSION=${TAG}" )
[ -n "${BASE_IMAGE:-}" ] && BUILD_ARGS+=( --build-arg "BASE_IMAGE=${BASE_IMAGE}" )

log "Building ${FULL} from source (context: ${SOURCE_DIR})"
docker build -f "${DOCKERFILE}" "${BUILD_ARGS[@]}" -t "${FULL}" "${SOURCE_DIR}"
log "Built ${FULL}"
log "Quick check:"
docker run --rm "${FULL}" valkey-server --version
