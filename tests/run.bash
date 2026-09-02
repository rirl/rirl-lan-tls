#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR

REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
readonly REPO_ROOT

readonly BATS_IMAGE='bats/bats:1.14.0@sha256:5322b877351fda0cc435de8c6116de7d0a2ec79d7c680132a0ef329a633bc66f'

exec docker run \
    --rm \
    --pull=never \
    --volume "${REPO_ROOT}:/workspace:ro" \
    --workdir /workspace \
    "${BATS_IMAGE}" \
    tests/renew-certificates.bats
