#!/usr/bin/env bash

set -Eeuo pipefail

umask 077

readonly PROGRAM_NAME="${0##*/}"
readonly CONFIG_FILE="${HOME}/.config/rirl-lan-tls/renew.conf"

CERTBOT_IMAGE='certbot/dns-cloudflare:v5.7.0'
CLOUDFLARE_CREDENTIALS="${HOME}/.config/rirl-lan-tls/certbot/cloudflare.ini"
LETSENCRYPT_DIR="${HOME}/.local/share/rirl-lan-tls/letsencrypt"

if [[ -f "${CONFIG_FILE}" ]]; then
    # shellcheck source=/dev/null
    source "${CONFIG_FILE}"
fi

usage() {
    cat <<USAGE
Usage: ${PROGRAM_NAME} [--dry-run]

Renew certificates using the repository-approved Certbot Docker image.

Options:
  --dry-run    Perform a Certbot renewal dry run.
  -h, --help   Show this help.
USAGE
}

dry_run=false

while (($# > 0)); do
    case "$1" in
        --dry-run)
            dry_run=true
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        *)
            printf 'ERROR: unsupported argument: %s\n' "$1" >&2
            usage >&2
            exit 2
            ;;
    esac

    shift
done

for command in docker stat; do
    if ! command -v "${command}" >/dev/null 2>&1; then
        printf 'ERROR: required command not found: %s\n' "${command}" >&2
        exit 1
    fi
done

if [[ ! -f "${CLOUDFLARE_CREDENTIALS}" ]]; then
    printf 'ERROR: Cloudflare credentials file not found: %s\n' \
        "${CLOUDFLARE_CREDENTIALS}" >&2
    exit 1
fi

credentials_mode="$(stat -c '%a' "${CLOUDFLARE_CREDENTIALS}")"

if [[ "${credentials_mode}" != '600' ]]; then
    printf 'ERROR: Cloudflare credentials must have mode 600; found %s: %s\n' \
        "${credentials_mode}" \
        "${CLOUDFLARE_CREDENTIALS}" >&2
    exit 1
fi

if [[ ! -d "${LETSENCRYPT_DIR}" ]]; then
    printf 'ERROR: Certbot state directory not found: %s\n' \
        "${LETSENCRYPT_DIR}" >&2
    exit 1
fi

if ! docker info >/dev/null 2>&1; then
    printf 'ERROR: Docker daemon is unavailable to the current user.\n' >&2
    exit 1
fi

if ! docker image inspect "${CERTBOT_IMAGE}" >/dev/null 2>&1; then
    printf 'ERROR: approved Certbot image is not present locally: %s\n' \
        "${CERTBOT_IMAGE}" >&2
    printf 'ERROR: refusing to pull an image implicitly during renewal.\n' >&2
    exit 1
fi

certbot_arguments=(
    renew
    --non-interactive
)

if [[ "${dry_run}" == true ]]; then
    certbot_arguments+=(--dry-run)
fi

printf '[%s] Starting Certbot renewal using %s\n' \
    "$(date --iso-8601=seconds)" \
    "${CERTBOT_IMAGE}"

docker run \
    --rm \
    --pull=never \
    --mount \
    "type=bind,src=${CLOUDFLARE_CREDENTIALS},dst=/cloudflare.ini,readonly" \
    --mount \
    "type=bind,src=${LETSENCRYPT_DIR},dst=/etc/letsencrypt" \
    "${CERTBOT_IMAGE}" \
    "${certbot_arguments[@]}"

printf '[%s] Certbot renewal completed successfully.\n' \
    "$(date --iso-8601=seconds)"
