# rirl-lan-tls

Automation and operational documentation for issuing and renewing publicly trusted TLS certificates for internal services under:

```text
lan.rirl.dev
```

The project is designed for LAN-only services. No inbound Internet access or router port forwarding is required.

## Goals

- Keep existing `.local` hostnames unchanged.
- Use `lan.rirl.dev` as the dedicated internal TLS namespace.
- Obtain publicly trusted certificates from Let's Encrypt.
- Use ACME DNS-01 validation through Cloudflare DNS.
- Run Certbot from Docker rather than installing it directly on the host.
- Persist certificate state outside the Certbot container.
- Automate certificate renewal with `systemd`.
- Keep private services accessible only from the LAN.
- Support both Ubuntu and Windows on the physical host `atreides`, developed in separate phases.
- Keep Cloudflare credentials, private keys, issued certificates, and Certbot state outside Git.

## Current Validated Baseline

The Ubuntu workflow for `atreides.lan.rirl.dev` has been proven manually and through the repository automation.

Validated state:

- Cloudflare is authoritative for `rirl.dev`.
- DNSSEC is enabled and validated.
- The scoped Cloudflare API token has been validated.
- Let's Encrypt staging issuance succeeded.
- Let's Encrypt production issuance succeeded.
- The production certificate for `atreides.lan.rirl.dev` was issued successfully.
- ACME DNS TXT cleanup was verified.
- `certbot renew --dry-run` succeeded.
- The repository renewal wrapper succeeded.
- `git diff --check` passed.
- ShellCheck passed for the renewal script.
- Manual execution through the `systemd` service succeeded.
- `systemd-analyze --user verify` passed for the service and timer.
- User lingering is enabled.
- The renewal timer is enabled and active.

Current Certbot image:

```text
certbot/dns-cloudflare:v5.7.0
```

## Initial Target

The first implementation target is Ubuntu running on `atreides`.

```text
Physical host:   atreides
mDNS name:       atreides.local
TLS name:        atreides.lan.rirl.dev
```

The initial production certificate is:

```text
atreides.lan.rirl.dev
```

The existing `.local` identity remains unchanged.

For example:

```text
ssh atreides.local
```

can continue to be used while HTTPS services use:

```text
https://atreides.lan.rirl.dev
```

## Architecture

```text
Cloudflare DNS
  authoritative for rirl.dev
        |
        | ACME DNS-01 TXT records
        v
Let's Encrypt
        |
        | certificate issuance / renewal
        v
Dockerized Certbot
  certbot/dns-cloudflare:v5.7.0
        |
        +--> Cloudflare credential
        |    ~/.config/rirl-lan-tls/certbot/cloudflare.ini
        |
        +--> Persistent Certbot state
             ~/.local/share/rirl-lan-tls/letsencrypt
        |
        v
LAN-only services
```

The Certbot container is disposable.

The Cloudflare credential and Certbot state persist on the host outside Git.

## Security Model

This project intentionally separates public certificate validation from service exposure.

Let's Encrypt validates ownership using DNS-01. It does not need to connect to the local service.

Therefore the design requires:

```text
Public DNS access:     Yes, for ACME TXT records
Inbound LAN service:   LAN only
Internet port forward: No
Public web service:    No
```

Cloudflare API access uses a scoped API token.

The populated credential file must never be committed to Git.

The credential file is stored at:

```text
~/.config/rirl-lan-tls/certbot/cloudflare.ini
```

and must have mode:

```text
0600
```

Persistent Certbot state is stored at:

```text
~/.local/share/rirl-lan-tls/letsencrypt
```

That state includes ACME account information, renewal configuration, private keys, and issued certificates and must remain outside Git.

## Proven Manual Workflow

The production issuance workflow used:

```bash
docker run --rm \
  -v ~/.config/rirl-lan-tls/certbot/cloudflare.ini:/cloudflare.ini:ro \
  -v ~/.local/share/rirl-lan-tls/letsencrypt:/etc/letsencrypt \
  certbot/dns-cloudflare:v5.7.0 \
  certonly \
  --dns-cloudflare \
  --dns-cloudflare-credentials /cloudflare.ini \
  --dns-cloudflare-propagation-seconds 30 \
  --agree-tos \
  --non-interactive \
  --register-unsafely-without-email \
  -d atreides.lan.rirl.dev
```

The proven renewal dry-run used:

```bash
docker run --rm \
  -v ~/.config/rirl-lan-tls/certbot/cloudflare.ini:/cloudflare.ini:ro \
  -v ~/.local/share/rirl-lan-tls/letsencrypt:/etc/letsencrypt \
  certbot/dns-cloudflare:v5.7.0 \
  renew \
  --dry-run
```

The repository automation is intentionally based on this proven runtime model.

## Repository Layout

```text
rirl-lan-tls/
├── README.md
├── config/
│   ├── cloudflare.ini.example
│   └── renew.conf.example
├── docs/
│   └── renewal-automation.md
├── scripts/
│   └── renew-certificates.bash
├── systemd/
│   └── user/
│       ├── rirl-lan-tls-renew.service
│       └── rirl-lan-tls-renew.timer
└── .gitignore
```

Additional historical or operational artifacts may also exist in the repository.

## Repository Boundary

The repository contains:

- automation scripts,
- non-secret configuration templates,
- `systemd` unit definitions,
- operational documentation,
- repository-safe evidence and records.

The repository must not contain:

- Cloudflare API tokens,
- populated credential files,
- `.env` files containing secrets,
- private keys,
- PEM certificate material,
- PKCS#12 files,
- Certbot ACME account state,
- generated renewal state.

## External Runtime State

Cloudflare credential:

```text
~/.config/rirl-lan-tls/certbot/cloudflare.ini
```

Local renewal configuration:

```text
~/.config/rirl-lan-tls/renew.conf
```

Persistent Certbot state:

```text
~/.local/share/rirl-lan-tls/letsencrypt
```

Repository:

```text
~/projects/rirl-lan-tls
```

## Renewal Automation

The repository renewal wrapper is:

```text
scripts/renew-certificates.bash
```

Manual dry-run validation:

```bash
cd ~/projects/rirl-lan-tls

./scripts/renew-certificates.bash --dry-run
```

Manual ordinary renewal invocation:

```bash
./scripts/renew-certificates.bash
```

A successful ordinary invocation may report:

```text
Certificate not yet due for renewal
No renewals were attempted.
```

That is expected when the certificate is not yet within its renewal window.

The wrapper also verifies:

- the required commands are available,
- the Cloudflare credential file exists,
- the credential file has mode `0600`,
- the persistent Certbot state directory exists,
- Docker is available to the current user,
- the pinned Certbot image already exists locally.

Automated renewal uses:

```text
--pull=never
```

so an unattended timer run cannot silently upgrade the Certbot image.

Image upgrades are intended to be deliberate, validated, and committed separately.

## systemd Automation

Renewal is driven by a user-level `systemd` oneshot service and timer.

Tracked unit files:

```text
systemd/user/rirl-lan-tls-renew.service
systemd/user/rirl-lan-tls-renew.timer
```

Installed user-unit links:

```text
~/.config/systemd/user/rirl-lan-tls-renew.service
~/.config/systemd/user/rirl-lan-tls-renew.timer
```

The renewal timer evaluates twice daily:

```text
00:00
12:00
```

with:

```text
RandomizedDelaySec=30m
Persistent=true
```

Certbot itself decides whether a certificate is actually due for renewal.

## User Lingering

User lingering is enabled so the user systemd manager can execute the renewal timer without requiring an active interactive login.

Verify:

```bash
loginctl show-user "$USER" -p Linger
```

Expected:

```text
Linger=yes
```

## Timer Status

Check timer status:

```bash
systemctl --user status rirl-lan-tls-renew.timer
```

Show the next scheduled run:

```bash
systemctl --user list-timers rirl-lan-tls-renew.timer
```

The expected timer state is:

```text
active (waiting)
```

## Renewal Logs

Review all renewal-service logs:

```bash
journalctl --user \
  -u rirl-lan-tls-renew.service
```

Review logs from the current boot:

```bash
journalctl --user \
  -b \
  -u rirl-lan-tls-renew.service
```

## Disable Automation

Disable the timer without removing certificates, credentials, or Certbot state:

```bash
systemctl --user disable --now rirl-lan-tls-renew.timer
```

The external runtime state remains untouched.

## Validation Record

The current Ubuntu renewal automation has passed the following checks:

```text
Manual Certbot staging issuance        PASS
Manual Certbot production issuance     PASS
Manual Certbot renewal dry-run         PASS
Repository wrapper dry-run             PASS
git diff --check                       PASS
ShellCheck                             PASS
Manual systemd service execution       PASS
systemd unit verification              PASS
User lingering                         ENABLED
Renewal timer                          ENABLED / ACTIVE
```

## Certificate Naming Strategy

The current namespace boundary is:

```text
lan.rirl.dev
```

Current host certificate:

```text
atreides.lan.rirl.dev
```

Possible future service names include:

```text
openwebui.atreides.lan.rirl.dev
ollama.atreides.lan.rirl.dev
mcp.atreides.lan.rirl.dev
```

A wildcard certificate such as:

```text
*.atreides.lan.rirl.dev
```

may be considered later, but it is not required for the current validated baseline.

## Ubuntu Status

The certificate issuance and renewal path for Ubuntu on `atreides` is operational.

Remaining work is service-specific integration, such as configuring individual LAN services to present the issued certificate and validating HTTPS from LAN clients.

## Windows Phase

The Windows implementation remains intentionally separate.

Future Windows work may address:

- Windows certificate storage,
- Docker Desktop or another suitable ACME runtime,
- secure Cloudflare credential storage,
- scheduled certificate renewal,
- service-specific certificate deployment,
- private-key separation between Ubuntu and Windows,
- naming policy for the dual-boot physical host.

The proven Ubuntu implementation should remain the reference baseline while the Windows design is developed.

## Documentation

Detailed renewal automation procedures are documented in:

```text
docs/renewal-automation.md
```

## Status

```text
Ubuntu certificate issuance:   VALIDATED
Ubuntu renewal automation:      OPERATIONAL
systemd renewal timer:          ENABLED
Windows certificate automation: DEFERRED
External service exposure:      OUT OF SCOPE
```
