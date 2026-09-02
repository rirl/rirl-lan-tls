# Certificate Consumer Reconciliation Architecture

## Decision

The current `rirl-lan-tls` certificate lifecycle uses state reconciliation as
its correctness and recovery mechanism.

Lifecycle:

```text
SCHEDULE -> RENEW -> ACTIVATE -> VERIFY
```

Operationally:

```text
SCHEDULE
   |
   v
Certbot renewal attempt
   |
   | success
   v
consumer RECONCILE
   |
   +--> compare desired certificate state
   |    with certificate actually served
   |
   +--> already equal
   |      no activation action
   |
   +--> different
          validate consumer
          activate/reload consumer
          verify convergence
```

A lifecycle is successful only when the required consumer proves convergence.

## Why Reconciliation Exists

A controlled forced-renewal experiment proved that certificate-file state and
served TLS state can legitimately diverge.

After Certbot successfully renewed the certificate:

```text
authoritative certificate on disk = new certificate
nginx certificate over TLS        = old certificate
```

The divergence persisted until nginx reloaded.

Therefore:

```text
certificate file is healthy
```

is not equivalent to:

```text
service is serving the authoritative certificate
```

## RECONCILE Contract

The stable consumer interface is:

```text
RECONCILE
```

Exit contract:

```text
0       consumer is proven converged on the currently authoritative certificate
nonzero convergence could not be established
```

The caller must not infer success from a reload command, health endpoint, or
certificate-status file.

## Repository Boundary

### `rirl-lan-tls`

Owns:

- schedule,
- preflight,
- Certbot renewal,
- invocation of required consumer reconciliation,
- aggregate lifecycle outcome.

Knows only:

```text
RECONCILE_COMMAND
exit 0 / nonzero
```

Must not know:

- nginx command lines,
- nginx container names,
- certificate paths inside the consumer,
- `/healthz`,
- `/status`,
- `cert-status`,
- fingerprint comparison implementation.

### `rirl-tls-nginx-validation`

Owns:

- desired certificate observation,
- served certificate observation,
- nginx validation,
- reload,
- health/canary behavior,
- convergence proof,
- concurrency control.

## Strategic Contract vs Tactical Deployment

The architectural relationship is:

```text
STRATEGIC CONTRACT
rirl-lan-tls -> RECONCILE interface
```

The current deployment is:

```text
TACTICAL CURRENT DEPLOYMENT
same physical host
both repositories checked out beneath ${HOME}/projects
RECONCILE_COMMAND points directly to consumer script
```

Current configuration:

```bash
RECONCILE_COMMAND="${HOME}/projects/rirl-tls-nginx-validation/scripts/reconcile.bash"
```

This filesystem colocation is **not** a strategic requirement.

It is a tactical expedient chosen because:

- there is currently one local consumer,
- both repositories already exist on the same host,
- the interface is proven,
- the immediate goal is to complete a reliable renewal lifecycle without
  introducing a premature distribution or service-discovery mechanism.

The tactical path must not be allowed to harden accidentally into the
architectural contract.

Future implementations may replace it with:

- an installed executable on `PATH`,
- a packaged command,
- a local service interface,
- a remote reconciliation API,
- a consumer registry,
- an event/fan-out mechanism,
- another controlled invocation mechanism.

Any such replacement should preserve the same semantics:

```text
invoke consumer reconciliation
0       convergence proven
nonzero convergence not established
```

This distinction allows deployment mechanics to evolve independently from
renewal correctness.

## Why Reconciliation Runs When Renewal Is Not Due

`RECONCILE` is not a Certbot deploy hook.

It is a correctness and recovery operation.

A scheduled Certbot invocation that reports:

```text
Certificate not yet due for renewal
No renewals were attempted.
```

still represents a successful renewal-stage evaluation.

Reconciliation follows it so that a stale consumer can recover even if the
current Certbot run did not issue a certificate.

## Why Deploy-Hook Fan-Out Is Deferred

Certbot deploy-hook/event-marker fan-out was considered but deliberately
deferred.

The current system has one required consumer and a simple local orchestration
path. Reconciliation provides correctness without introducing an event
distribution mechanism.

Revisit fan-out when concrete requirements appear, such as:

- multiple consumers,
- remote consumers,
- certificate distribution,
- independent consumer discovery,
- asynchronous activation.

## Validation

The consumer implementation has been validated with:

```text
22/22 Bats tests
6/6 live integration tests
```

`rirl-lan-tls` orchestration has been validated with:

```text
5/5 Bats tests
```

The real systemd service path has also been validated against an already
converged nginx consumer.

## Next Separate Concern

Consumer availability is separate from renewal correctness.

The current nginx validation container restart policy should be considered in a
separate availability phase rather than folded into reconciliation semantics.

Likewise, replacing tactical filesystem colocation should be handled as a
separate deployment/interface-hardening concern rather than mixed into the
renewal lifecycle itself.
