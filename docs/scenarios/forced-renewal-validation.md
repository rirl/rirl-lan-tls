# Forced renewal validation scenario

## Purpose

This scenario validates the full certificate lifecycle when Certbot is forced to
obtain a new certificate even if the existing certificate is not yet due for
renewal.

The lifecycle under test is:

```text
renewal -> consumer reconciliation -> proven served-certificate convergence
```

A successful Certbot renewal alone is not sufficient. The required consumer
must also reconcile successfully.

## Safety

A forced renewal uses the real ACME account and authoritative certificate state.
It can consume certificate-authority rate limits and changes the active
certificate lineage.

Use this scenario only when a real renewal is intentionally required for
validation. Prefer the repository dry-run path for routine testing.

Do not use this procedure merely to exercise nginx reconciliation. The nginx
consumer repository has a disposable live integration suite for that purpose.

## Preconditions

Confirm the renewal configuration exists and is protected:

```bash
test -f "${HOME}/.config/rirl-lan-tls/renew.conf"
test "$(stat -c '%a' "${HOME}/.config/rirl-lan-tls/certbot/cloudflare.ini")" = 600
```

Confirm Docker is available:

```bash
docker info >/dev/null
```

Confirm the configured RECONCILE command is executable:

```bash
RECONCILE_COMMAND="$(
  sed -n 's/^RECONCILE_COMMAND=//p' \
    "${HOME}/.config/rirl-lan-tls/renew.conf"
)"

test -n "${RECONCILE_COMMAND}"
test -x "${RECONCILE_COMMAND}"
```

## Reproduce

From the repository root:

```bash
./scripts/renew-certificates.bash --force-renewal
```

The wrapper runs Certbot first. If the Certbot stage succeeds, it invokes the
configured consumer RECONCILE command.

## Expected behavior

Expected lifecycle behavior:

1. renewal preflight succeeds;
2. Certbot obtains a new certificate generation;
3. the renewal stage exits successfully;
4. the configured consumer RECONCILE operation runs;
5. RECONCILE proves the consumer is serving the currently authoritative
   certificate;
6. the wrapper exits `0` only when the complete lifecycle succeeds.

If Certbot fails, RECONCILE must not be invoked.

If Certbot succeeds but RECONCILE fails, the lifecycle must return nonzero.

## Verification

Review the renewal-service output or terminal output for both stages.

The consumer's RECONCILE implementation is responsible for proving served TLS
state independently from filesystem certificate state.

Do not treat certificate files, `/healthz`, or status metadata alone as proof
that the renewed certificate is being served.

## Historical validation

The completed forced-renewal experiment is retained under:

```text
docs/evidence/2026-08-30-forced-renewal-validation/
```

That directory is historical evidence of what was actually observed. This
document describes how to reproduce the lifecycle deliberately.
