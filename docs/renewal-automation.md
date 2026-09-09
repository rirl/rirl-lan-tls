# rirl.dev Certificate Renewal Automation

## Purpose

This automation renews certificates issued for the internal `lan.rirl.dev`
namespace using Certbot's Cloudflare DNS plugin in Docker.

The workflow is based on the manually validated configuration using:

- Cloudflare authoritative DNS for `rirl.dev`
- a scoped Cloudflare API token
- `certbot/dns-cloudflare:v5.7.0`
- DNS-01 ACME validation
- persistent Certbot state outside Git
- a configured consumer `RECONCILE` command

The operational lifecycle is:

```text
SCHEDULE -> RENEW -> ACTIVATE -> VERIFY
```

For the current implementation, ACTIVATE and VERIFY are implemented through
consumer state reconciliation after every successful Certbot invocation.

## Reconciliation Contract

`rirl-lan-tls` invokes the configured consumer reconciliation command after
Certbot completes successfully.

The consumer contract is:

```text
exit 0     consumer is proven converged on the currently authoritative certificate
nonzero    convergence could not be established
```

A successful Certbot invocation is therefore not sufficient by itself for the
overall lifecycle to succeed.

Reconciliation also runs when Certbot reports that no certificate is currently
due for renewal. This is intentional: reconciliation is a correctness and
recovery mechanism, not merely a renewal hook.

`rirl-lan-tls` does not depend on consumer-specific details such as nginx
commands, container names, `/healthz`, `/status`, `cert-status`, or certificate
fingerprint implementation.

## Tactical Deployment Assumption

The current deployment assumes that `rirl-lan-tls` and
`rirl-tls-nginx-validation` are present on the same host and that the consumer
entry point is reached through a configured filesystem path:

```bash
RECONCILE_COMMAND="${HOME}/projects/rirl-tls-nginx-validation/scripts/reconcile.bash"
```

This is a tactical deployment choice, not a strategic architecture requirement.

The strategic dependency is only:

```text
invoke RECONCILE
exit 0     convergence proven
nonzero    convergence not established
```

The current same-host repository layout and direct checkout path are simply how
that interface is located today.

Future implementations may replace this with an installed command, package,
service interface, remote invocation mechanism, consumer registry, or
event/fan-out mechanism without changing the lifecycle semantics.

## Security Boundary

The repository contains automation only.

The following must remain outside Git:

```text
~/.config/rirl-lan-tls/certbot/cloudflare.ini
~/.config/rirl-lan-tls/renew.conf
~/.local/share/rirl-lan-tls/letsencrypt/
```

The Cloudflare credentials file must have mode `0600`.

## Runtime Paths

Cloudflare credentials:

```text
~/.config/rirl-lan-tls/certbot/cloudflare.ini
```

Certbot state:

```text
~/.local/share/rirl-lan-tls/letsencrypt
```

Repository:

```text
~/projects/rirl-lan-tls
```

Current tactical consumer path:

```text
~/projects/rirl-tls-nginx-validation/scripts/reconcile.bash
```

## Manual Renewal Validation

Before enabling unattended renewal, run:

```bash
cd ~/projects/rirl-lan-tls
./scripts/renew-certificates.bash --dry-run
```

The command must complete successfully.

A successful dry run now includes consumer reconciliation after Certbot
completes.

Then test an ordinary renewal invocation:

```bash
./scripts/renew-certificates.bash
```

A successful invocation may report that no certificates are currently due for
renewal. Consumer reconciliation still runs afterward.

## Install the systemd User Units

```bash
mkdir -p ~/.config/systemd/user

ln -sfn \
  ~/projects/rirl-lan-tls/systemd/user/rirl-lan-tls-renew.service \
  ~/.config/systemd/user/rirl-lan-tls-renew.service

ln -sfn \
  ~/projects/rirl-lan-tls/systemd/user/rirl-lan-tls-renew.timer \
  ~/.config/systemd/user/rirl-lan-tls-renew.timer

systemctl --user daemon-reload
```

## Validate the Service Before Enabling the Timer

```bash
systemctl --user start rirl-lan-tls-renew.service
systemctl --user status rirl-lan-tls-renew.service
journalctl --user -u rirl-lan-tls-renew.service --since today
```

A successful service invocation should show Certbot completion followed by
consumer reconciliation.

Do not enable the timer until the service invocation succeeds.

## Enable Unattended User Services

```bash
sudo loginctl enable-linger "$USER"
loginctl show-user "$USER" -p Linger
```

Expected:

```text
Linger=yes
```

## Enable the Timer

```bash
systemctl --user enable --now rirl-lan-tls-renew.timer
systemctl --user status rirl-lan-tls-renew.timer
systemctl --user list-timers rirl-lan-tls-renew.timer
```

## Scheduling Policy

The timer evaluates renewal twice daily, at approximately midnight and noon,
with a randomized delay of up to 30 minutes.

`Persistent=true` causes systemd to run a missed timer after the user manager
becomes available again.

Certbot itself determines whether any certificate is sufficiently close to
expiration to require renewal.

Consumer reconciliation runs after every successful Certbot invocation,
including successful not-due checks.

## Logs

```bash
journalctl --user -u rirl-lan-tls-renew.service
journalctl --user -b -u rirl-lan-tls-renew.service
```

A successful not-due run should contain messages equivalent to:

```text
Certificate not yet due for renewal
No renewals were attempted.
Certbot renewal completed successfully.
Starting consumer reconciliation.
Already converged: ... No reload performed.
Consumer reconciliation completed successfully.
```

## Disable Automation

```bash
systemctl --user disable --now rirl-lan-tls-renew.timer
```

The certificates, Cloudflare credentials, and Certbot state remain untouched.

## Docker Image Policy

Automated renewal uses the explicitly configured image:

```text
certbot/dns-cloudflare:v5.7.0
```

The renewal script uses `--pull=never` and verifies that the image already
exists locally. Image upgrades should be deliberate, dry-run tested, and
committed as a separate controlled change.

## Deferred Fan-Out

Certbot deploy-hook/event-marker fan-out remains intentionally deferred.

State reconciliation is the current correctness and recovery mechanism.

Revisit fan-out only when concrete requirements justify it, such as multiple
consumers, remote distribution, or asynchronous consumer activation.
