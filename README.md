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
- Automate certificate renewal.
- Keep private services accessible only from the LAN.
- Support both Ubuntu and Windows on the physical host `atreides`, developed in separate phases.

## Initial Target

The first implementation target is Ubuntu running on `atreides`.

```text
Physical host:   atreides
mDNS name:       atreides.local
TLS name:        atreides.lan.rirl.dev
```

The initial certificate is:

```text
atreides.lan.rirl.dev
```

After the basic workflow is proven, an optional wildcard certificate may be introduced:

```text
*.atreides.lan.rirl.dev
```

This can support service names such as:

```text
openwebui.atreides.lan.rirl.dev
ollama.atreides.lan.rirl.dev
mcp.atreides.lan.rirl.dev
```

## Architecture

```text
Squarespace
  registrar / parent DNS for rirl.dev
        |
        | delegates lan.rirl.dev
        v
Cloudflare DNS
  authoritative for lan.rirl.dev
        |
        | ACME DNS-01 TXT records
        v
Let's Encrypt
        |
        | certificate issuance
        v
Dockerized Certbot
  certbot/dns-cloudflare
        |
        v
Persistent certificate state
  /opt/acme
        |
        v
LAN-only services
```

The DNS name used for TLS does not replace the host's `.local` identity.

For example:

```text
ssh atreides.local
```

can continue to be used while HTTPS tooling uses:

```text
https://atreides.lan.rirl.dev
```

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

Cloudflare API access should use a restricted API token with DNS edit permission only for the relevant zone.

Credentials and private keys must never be committed to Git.

## Current Implementation Phase

### Phase 1 — Ubuntu

The Ubuntu phase establishes and verifies the complete certificate lifecycle:

1. Delegate `lan.rirl.dev` to Cloudflare.
2. Verify authoritative DNS delegation.
3. Create a restricted Cloudflare API token.
4. Create persistent Certbot storage.
5. Run the current stable `certbot/dns-cloudflare` image in Docker.
6. Obtain a Let's Encrypt staging certificate.
7. Verify renewal with `certbot renew --dry-run`.
8. Obtain the production certificate.
9. Inspect the certificate with OpenSSL.
10. Automate renewal with systemd.
11. Resolve `atreides.lan.rirl.dev` on the LAN.
12. Validate the certificate with a local HTTPS service.

The Ubuntu implementation is documented in:

```text
docs/lets-encrypt-lan-rirl-dev-ubuntu-first.md
```

### Phase 2 — Windows

The Windows implementation is intentionally deferred until the Ubuntu workflow is proven.

The Windows phase will address:

- Windows certificate storage
- Docker Desktop or another suitable ACME runtime
- secure Cloudflare credential storage
- scheduled certificate renewal
- service-specific certificate deployment
- private-key separation between Ubuntu and Windows
- naming policy for a dual-boot physical host

No Windows certificate architecture should be considered final until the Ubuntu implementation is complete.

## Proposed Repository Layout

```text
rirl-lan-tls/
├── README.md
├── docs/
│   └── lets-encrypt-lan-rirl-dev-ubuntu-first.md
├── docker/
├── scripts/
├── systemd/
├── windows/
└── .gitignore
```

The directories can be populated incrementally as the manual procedure is converted into automation.

## Persistent Ubuntu State

The intended host-side Certbot layout is:

```text
/opt/acme/
├── credentials/
│   └── cloudflare.ini
├── etc/
├── lib/
└── log/
```

Container mappings:

```text
/opt/acme/etc  -> /etc/letsencrypt
/opt/acme/lib  -> /var/lib/letsencrypt
/opt/acme/log  -> /var/log/letsencrypt
```

The Certbot container is disposable. Certificate and ACME account state remain on the host.

## Git Safety

At minimum, the repository should exclude secrets and generated certificate material.

Suggested `.gitignore` entries:

```gitignore
# Secrets
*.ini
*.env
.env
credentials/
secrets/

# Private keys and certificate material
*.key
*.pem
*.p12
*.pfx

# ACME runtime state
letsencrypt/
acme-state/

# Local overrides
*.local
```

Do not place the Cloudflare API token in this repository, even in a private GitHub repository.

## Certificate Naming Strategy

The current namespace boundary is:

```text
lan.rirl.dev
```

Initial host certificate:

```text
atreides.lan.rirl.dev
```

Possible later host wildcard:

```text
*.atreides.lan.rirl.dev
```

A wildcard should be introduced only after the single-host certificate lifecycle is working reliably.

## Completion Criteria for Ubuntu

The Ubuntu phase is complete only when:

- `lan.rirl.dev` is authoritatively served by Cloudflare.
- Dockerized Certbot can create and remove DNS-01 challenge records.
- staging issuance succeeds.
- renewal dry-run succeeds.
- production issuance succeeds.
- the certificate contains the expected SAN.
- the renewal timer is enabled and tested.
- LAN clients resolve `atreides.lan.rirl.dev`.
- a local HTTPS service presents the certificate successfully.

Only then should the project proceed to the Windows phase.

## Documentation

Start here:

```text
docs/lets-encrypt-lan-rirl-dev-ubuntu-first.md
```

That document contains the checkpoint-driven Ubuntu procedure from DNS delegation through automated certificate renewal and local HTTPS validation.

## Status

```text
Ubuntu certificate automation: Planned / implementation in progress
Windows certificate automation: Deferred
External service exposure:      Out of scope
```
