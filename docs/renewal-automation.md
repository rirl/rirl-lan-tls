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

## Manual Renewal Validation

Before enabling unattended renewal, run:

```bash
cd ~/projects/rirl-lan-tls
./scripts/renew-certificates.bash --dry-run
```

The command must complete successfully.

Then test an ordinary renewal invocation:

```bash
./scripts/renew-certificates.bash
```

A successful invocation may report that no certificates are currently due for
renewal.

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

## Logs

```bash
journalctl --user -u rirl-lan-tls-renew.service
journalctl --user -b -u rirl-lan-tls-renew.service
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
