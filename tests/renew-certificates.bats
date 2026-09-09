#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd -- "${BATS_TEST_DIRNAME}/.." && pwd)"
    export REPO_ROOT

    export HOME="${BATS_TEST_TMPDIR}/home"
    mkdir -p \
        "${HOME}/.config/rirl-lan-tls/certbot" \
        "${HOME}/.local/share/rirl-lan-tls/letsencrypt" \
        "${BATS_TEST_TMPDIR}/bin"

    printf '%s\n' 'dns_cloudflare_api_token = test-token' \
        > "${HOME}/.config/rirl-lan-tls/certbot/cloudflare.ini"
    chmod 600 "${HOME}/.config/rirl-lan-tls/certbot/cloudflare.ini"

    cp "${REPO_ROOT}/tests/fixtures/bin/docker" "${BATS_TEST_TMPDIR}/bin/docker"
    cp "${REPO_ROOT}/tests/fixtures/bin/date" "${BATS_TEST_TMPDIR}/bin/date"
    chmod +x "${BATS_TEST_TMPDIR}/bin/docker" "${BATS_TEST_TMPDIR}/bin/date"

    export PATH="${BATS_TEST_TMPDIR}/bin:${PATH}"
    export FAKE_DOCKER_LOG="${BATS_TEST_TMPDIR}/docker.log"
    : > "${FAKE_DOCKER_LOG}"

    export RECONCILE_LOG="${BATS_TEST_TMPDIR}/reconcile.log"
}

write_config() {
    local reconcile_command="$1"
    cat > "${HOME}/.config/rirl-lan-tls/renew.conf" <<EOF
RECONCILE_COMMAND='${reconcile_command}'
EOF
}

make_reconcile() {
    local exit_code="$1"
    local command_path="${BATS_TEST_TMPDIR}/reconcile-${exit_code}.bash"

    cat > "${command_path}" <<EOF
#!/usr/bin/env sh
printf '%s\n' called >> '${RECONCILE_LOG}'
exit ${exit_code}
EOF
    chmod +x "${command_path}"
    printf '%s\n' "${command_path}"
}

assert_no_certbot_run() {
    ! grep -q '^run ' "${FAKE_DOCKER_LOG}"
}

assert_certbot_run() {
    grep -q '^run ' "${FAKE_DOCKER_LOG}"
}

@test "missing RECONCILE_COMMAND fails before Certbot" {
    run "${REPO_ROOT}/scripts/renew-certificates.bash"
    [ "${status}" -eq 1 ]
    [[ "${output}" == *"RECONCILE_COMMAND is not configured"* ]]
    assert_no_certbot_run
}

@test "non-executable RECONCILE_COMMAND fails before Certbot" {
    local command_path="${BATS_TEST_TMPDIR}/not-executable"
    : > "${command_path}"
    chmod 600 "${command_path}"
    write_config "${command_path}"

    run "${REPO_ROOT}/scripts/renew-certificates.bash"
    [ "${status}" -eq 1 ]
    [[ "${output}" == *"RECONCILE_COMMAND is not executable"* ]]
    assert_no_certbot_run
}

@test "Certbot success and reconcile success returns 0" {
    local command_path
    command_path="$(make_reconcile 0)"
    write_config "${command_path}"

    run "${REPO_ROOT}/scripts/renew-certificates.bash"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"Certbot renewal completed successfully."* ]]
    [[ "${output}" == *"Consumer reconciliation completed successfully."* ]]
    assert_certbot_run
    [ "$(wc -l < "${RECONCILE_LOG}")" -eq 1 ]
}

@test "Certbot success and reconcile failure returns 1" {
    local command_path
    command_path="$(make_reconcile 1)"
    write_config "${command_path}"

    run "${REPO_ROOT}/scripts/renew-certificates.bash"
    [ "${status}" -eq 1 ]
    [[ "${output}" == *"Certbot renewal completed successfully."* ]]
    [[ "${output}" == *"ERROR: consumer reconciliation failed."* ]]
    assert_certbot_run
    [ "$(wc -l < "${RECONCILE_LOG}")" -eq 1 ]
}

@test "Certbot failure does not invoke reconcile" {
    local command_path
    command_path="$(make_reconcile 0)"
    write_config "${command_path}"
    export FAKE_DOCKER_RUN_EXIT=42

    run "${REPO_ROOT}/scripts/renew-certificates.bash"
    [ "${status}" -eq 42 ]
    assert_certbot_run
    [ ! -e "${RECONCILE_LOG}" ]
    [[ "${output}" != *"Starting consumer reconciliation."* ]]
}
