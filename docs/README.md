# Documentation

This directory contains design, build, and operational documentation for the
`rirl-lan-tls` project.

Current guides:

- `lets-encrypt-lan-rirl-dev-ubuntu-first.md`
- `renewal-automation.md`
- `reconciliation-architecture.md`

The current operational lifecycle is:

```text
SCHEDULE -> RENEW -> ACTIVATE -> VERIFY
```

For the current implementation, ACTIVATE and VERIFY are provided through the
consumer `RECONCILE` interface.

The present same-host repository colocation and direct filesystem path used to
locate `RECONCILE` are explicitly tactical deployment choices. The strategic
contract is the reconciliation interface and its exit semantics, not the
filesystem layout.

## Reproducible scenarios

- `scenarios/forced-renewal-validation.md` — deliberate end-to-end forced
  renewal and consumer reconciliation.
- `scenarios/systemd-timer-recovery.md` — restore and verify the user-level
  renewal timer.

Scenario documents describe how to reproduce behavior. `evidence/` preserves
records of validation runs that were actually performed.
