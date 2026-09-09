#!/usr/bin/env bash

set -Eeuo pipefail

readonly BATS_IMAGE='docker.io/bats/bats:1.14.0@sha256:5322b877351fda0cc435de8c6116de7d0a2ec79d7c680132a0ef329a633bc66f'

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
results_dir="${BATS_TEST_RESULTS_DIR:-${repo_root}/test-results/unit}"
mkdir -p -- "${results_dir}"
results_dir="$(cd -- "${results_dir}" && pwd)"

runtime_options=(
    run
    --rm
    --user "$(id -u):$(id -g)"
    --volume "${repo_root}:/code:ro"
    --volume "${results_dir}:/test-results"
    --workdir /code
)

set +e
docker "${runtime_options[@]}" \
    "${BATS_IMAGE}" \
    --formatter tap \
    --report-formatter junit \
    --output /test-results \
    --print-output-on-failure \
    tests/renew-certificates.bats \
    | tee "${results_dir}/report.tap"
pipeline_status=("${PIPESTATUS[@]}")
set -e

bats_status="${pipeline_status[0]}"
tee_status="${pipeline_status[1]}"

if ((bats_status != 0)); then
    exit "${bats_status}"
fi

if ((tee_status != 0)); then
    printf 'ERROR: could not write TAP report: %s\n' \
        "${results_dir}/report.tap" >&2
    exit "${tee_status}"
fi
