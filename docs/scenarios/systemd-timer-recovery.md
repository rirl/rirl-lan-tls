# systemd renewal timer recovery scenario

## Purpose

This scenario verifies that the user-level renewal timer is installed, enabled,
active, and capable of invoking the repository renewal service.

It also describes how to restore the timer when it has been disabled or its
installed unit files no longer match the repository versions.

## Safety

This scenario uses the real user-level systemd service.

Starting the service manually runs the normal renewal wrapper. Certbot decides
whether any certificate is due for renewal, and reconciliation follows a
successful renewal-stage evaluation.

For a non-production renewal check, use the repository dry-run workflow instead.

## Inspect current state

Check the timer:

```bash
systemctl --user status rirl-lan-tls-renew.timer
systemctl --user list-timers rirl-lan-tls-renew.timer
```

Check whether it is enabled:

```bash
systemctl --user is-enabled rirl-lan-tls-renew.timer
```

Inspect the installed unit definitions:

```bash
systemctl --user cat rirl-lan-tls-renew.service
systemctl --user cat rirl-lan-tls-renew.timer
```

## Restore repository unit files

Copy the repository units into the user systemd directory:

```bash
mkdir -p "${HOME}/.config/systemd/user"

cp systemd/user/rirl-lan-tls-renew.service \
  "${HOME}/.config/systemd/user/"

cp systemd/user/rirl-lan-tls-renew.timer \
  "${HOME}/.config/systemd/user/"
```

Reload the user systemd manager:

```bash
systemctl --user daemon-reload
```

Verify the units:

```bash
systemd-analyze --user verify \
  "${HOME}/.config/systemd/user/rirl-lan-tls-renew.service" \
  "${HOME}/.config/systemd/user/rirl-lan-tls-renew.timer"
```

Enable and start the timer:

```bash
systemctl --user enable --now rirl-lan-tls-renew.timer
```

## Expected timer behavior

The timer should report enabled and active.

The repository timer uses persistent scheduling so a missed invocation can be
recovered after the user systemd manager resumes. Its randomized delay remains
part of the normal schedule.

## Optional manual service validation

To exercise the installed service path immediately:

```bash
systemctl --user start rirl-lan-tls-renew.service
```

Then inspect its result:

```bash
systemctl --user status rirl-lan-tls-renew.service

journalctl --user \
  -u rirl-lan-tls-renew.service \
  --since today
```

A successful run can legitimately report that no certificate is currently due
for renewal. Reconciliation still follows a successful renewal-stage evaluation.

## Historical validation

The completed timer-restoration evidence is retained under:

```text
docs/evidence/2026-08-31-renewal-timer-restoration/
```

That directory records actual timer state and a scheduled renewal run. This
document describes the reproducible recovery procedure.
