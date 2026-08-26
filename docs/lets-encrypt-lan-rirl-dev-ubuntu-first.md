# Let's Encrypt for `lan.rirl.dev` — Ubuntu First, Windows Later

## Goal

Set up automated Let's Encrypt certificate issuance on **Ubuntu running on `atreides`** using:

- `rirl.dev` as the registered domain
- `lan.rirl.dev` as the internal TLS namespace
- Cloudflare DNS for ACME DNS-01 automation
- Dockerized Certbot using the official `certbot/dns-cloudflare` image
- persistent certificate state on the Ubuntu filesystem
- no inbound Internet exposure
- no router port forwarding
- no need to change the existing `.local` hostnames yet

Initial certificate target:

```text
atreides.lan.rirl.dev
```

Optional later wildcard target:

```text
*.atreides.lan.rirl.dev
```

The Windows setup is intentionally deferred until the Ubuntu workflow has been proven end-to-end.

---

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
        | DNS-01 TXT record via API
        v
Let's Encrypt
        |
        | issues certificate
        v
Dockerized Certbot on Ubuntu
        |
        v
Persistent certificate files on atreides
```

The certificate name is independent of the machine's mDNS name.

You can continue using:

```text
atreides.local
```

while TLS-aware tooling uses:

```text
atreides.lan.rirl.dev
```

---

# Phase 0 — Preconditions

Before changing DNS, confirm the following.

- [ ] `rirl.dev` is registered and manageable in Squarespace.
- [ ] You can edit DNS records for `rirl.dev` in Squarespace.
- [ ] You have or can create a Cloudflare account.
- [ ] Docker works on Ubuntu on `atreides`.
- [ ] You are booted into Ubuntu on `atreides`.
- [ ] You have `sudo` access.

Check Docker:

```bash
docker version
```

Expected result: both **Client** and **Server** sections are present.

---

# Phase 1 — Decide the DNS Delegation Boundary

We will use:

```text
lan.rirl.dev
```

as a dedicated DNS zone for internal TLS names.

This avoids moving all of `rirl.dev` to Cloudflare and isolates the ACME automation boundary.

The intended delegation is:

```text
rirl.dev                  -> Squarespace DNS
lan.rirl.dev              -> Cloudflare DNS
atreides.lan.rirl.dev     -> resolved for LAN use
```

---

# Phase 2 — Create `lan.rirl.dev` in Cloudflare

## 2.1 Add the zone

In Cloudflare, create/add the DNS zone:

```text
lan.rirl.dev
```

Cloudflare should assign authoritative nameservers for that zone.

Record the assigned nameservers exactly.

Example only:

```text
alice.ns.cloudflare.com
bob.ns.cloudflare.com
```

Do **not** use the example values above.

### Checkpoint

You should now have the actual Cloudflare authoritative nameservers for:

```text
lan.rirl.dev
```

---

# Phase 3 — Delegate `lan.rirl.dev` from Squarespace

Squarespace supports adding NS records for subdomains. Its current documentation notes that DNSSEC must be disabled before adding subdomain NS records.

## 3.1 Review DNSSEC first

In Squarespace:

1. Open the domain dashboard for `rirl.dev`.
2. Open **DNS**.
3. Open **DNSSEC**.
4. Determine whether DNSSEC is currently enabled.

If Squarespace requires DNSSEC to be disabled before adding the delegation, disable it before proceeding.

Do not remove unrelated DNS records for `rirl.dev`.

## 3.2 Add NS delegation records

Create NS records that delegate:

```text
lan.rirl.dev
```

to the Cloudflare nameservers obtained in Phase 2.

Conceptually:

```text
lan.rirl.dev.  NS  <cloudflare-nameserver-1>
lan.rirl.dev.  NS  <cloudflare-nameserver-2>
```

Squarespace may expect only the subdomain label in its UI rather than the full FQDN. Follow the UI semantics shown for the domain.

### Important

Do **not** change the authoritative nameservers for the entire `rirl.dev` domain.

We are delegating only:

```text
lan.rirl.dev
```

---

# Phase 4 — Verify DNS Delegation from Ubuntu

Install DNS utilities if needed:

```bash
sudo apt update
sudo apt install -y dnsutils
```

Check the delegation:

```bash
dig NS lan.rirl.dev
```

Also trace it:

```bash
dig +trace NS lan.rirl.dev
```

Expected result: the authoritative nameservers ultimately shown for `lan.rirl.dev` are the Cloudflare nameservers assigned in Phase 2.

You can also query one directly:

```bash
dig @<cloudflare-nameserver> NS lan.rirl.dev
```

### Stop here if delegation is not correct

Do not proceed to Certbot until:

```text
lan.rirl.dev
```

is authoritatively served by Cloudflare.

---

# Phase 5 — Create the LAN Host Record

For the first test, create a DNS record for:

```text
atreides.lan.rirl.dev
```

There are two reasonable designs.

## Option A — Publish the RFC1918 address in Cloudflare DNS

Create an A record such as:

```text
atreides.lan.rirl.dev -> 192.168.1.x
```

This is simple and works on the LAN, but publicly exposes the private IP mapping in DNS.

## Option B — Keep host resolution local

Use your LAN DNS resolver/router/hosts-file to resolve:

```text
atreides.lan.rirl.dev -> 192.168.1.x
```

while Cloudflare is used only for the `_acme-challenge` records required by Let's Encrypt.

For a privacy-conscious home-lab setup, **Option B is preferable**.

For the very first certificate issuance, host resolution is not required by Let's Encrypt because DNS-01 validation depends on the TXT challenge record, not the A record.

---

# Phase 6 — Create a Restricted Cloudflare API Token

Use a scoped API token, not the legacy Global API Key.

In Cloudflare:

1. Open **My Profile**.
2. Open **API Tokens**.
3. Select **Create Token**.
4. Use the **Edit zone DNS** template or create an equivalent custom token.
5. Restrict the token to the zone used for `lan.rirl.dev`.
6. Give it only the DNS permissions required for challenge record creation/deletion.

The intended capability is approximately:

```text
Zone / DNS / Edit
```

for the relevant zone only.

Do not grant broader account-level permissions unless necessary.

Copy the API token when Cloudflare displays it.

The secret is normally shown only once.

---

# Phase 7 — Create the Persistent Certbot Directory Layout

On Ubuntu:

```bash
sudo mkdir -p /opt/acme/{credentials,etc,lib,log}
sudo chown -R root:root /opt/acme
sudo chmod 700 /opt/acme
sudo chmod 700 /opt/acme/credentials
```

The resulting structure is:

```text
/opt/acme/
├── credentials/
├── etc/
├── lib/
└── log/
```

Purpose:

```text
/opt/acme/etc  -> /etc/letsencrypt
/opt/acme/lib  -> /var/lib/letsencrypt
/opt/acme/log  -> /var/log/letsencrypt
```

The Docker container remains disposable. The certificate state remains on the host.

---

# Phase 8 — Store the Cloudflare Token Securely

Create:

```bash
sudo vi /opt/acme/credentials/cloudflare.ini
```

Contents:

```ini
dns_cloudflare_api_token = YOUR_CLOUDFLARE_API_TOKEN
```

Then lock it down:

```bash
sudo chown root:root /opt/acme/credentials/cloudflare.ini
sudo chmod 600 /opt/acme/credentials/cloudflare.ini
```

Verify:

```bash
sudo ls -l /opt/acme/credentials/cloudflare.ini
```

Expected permissions:

```text
-rw-------
```

Do not put this file in Git.

---

# Phase 9 — Pull the Current Stable Certbot Cloudflare Image

Use the official Cloudflare-enabled Certbot image:

```bash
sudo docker pull certbot/dns-cloudflare:latest
```

Confirm it exists locally:

```bash
sudo docker image inspect certbot/dns-cloudflare:latest \
  --format '{{.RepoTags}} {{.Id}}'
```

Capture the immutable digest used for this run:

```bash
sudo docker image inspect certbot/dns-cloudflare:latest \
  --format '{{index .RepoDigests 0}}'
```

Optional but recommended: save that digest to your operational notes.

---

# Phase 10 — Verify the Certbot Runtime Before Requesting a Certificate

Run:

```bash
sudo docker run --rm \
  certbot/dns-cloudflare:latest \
  --version
```

Also verify the Cloudflare plugin is present:

```bash
sudo docker run --rm \
  certbot/dns-cloudflare:latest \
  plugins
```

Expected output should include the Cloudflare DNS authenticator.

---

# Phase 11 — Perform a Let's Encrypt Staging Test

Use the Let's Encrypt staging environment first to avoid production rate limits while validating the workflow.

Replace:

```text
YOUR_EMAIL_ADDRESS
```

with the email address you want associated with the ACME account.

Run:

```bash
sudo docker run --rm \
  -v /opt/acme/etc:/etc/letsencrypt \
  -v /opt/acme/lib:/var/lib/letsencrypt \
  -v /opt/acme/log:/var/log/letsencrypt \
  -v /opt/acme/credentials:/root/.secrets:ro \
  certbot/dns-cloudflare:latest \
  certonly \
  --staging \
  --dns-cloudflare \
  --dns-cloudflare-credentials /root/.secrets/cloudflare.ini \
  --dns-cloudflare-propagation-seconds 30 \
  --non-interactive \
  --agree-tos \
  --email YOUR_EMAIL_ADDRESS \
  -d atreides.lan.rirl.dev
```

### What should happen

Certbot should:

1. request a DNS-01 challenge from Let's Encrypt staging;
2. create a temporary TXT record under Cloudflare;
3. wait for DNS propagation;
4. allow Let's Encrypt to validate the TXT record;
5. remove the challenge TXT record;
6. save the certificate state under `/opt/acme/etc`.

### Checkpoint

List certificates:

```bash
sudo docker run --rm \
  -v /opt/acme/etc:/etc/letsencrypt \
  -v /opt/acme/lib:/var/lib/letsencrypt \
  -v /opt/acme/log:/var/log/letsencrypt \
  certbot/dns-cloudflare:latest \
  certificates
```

You should see:

```text
atreides.lan.rirl.dev
```

Because this is staging, the certificate is intentionally not browser-trusted.

---

# Phase 12 — Inspect the Persisted Certificate Files

Check:

```bash
sudo find /opt/acme/etc/live -maxdepth 2 -type l -ls
```

The expected lineage is approximately:

```text
/opt/acme/etc/live/atreides.lan.rirl.dev/
├── cert.pem
├── chain.pem
├── fullchain.pem
└── privkey.pem
```

Applications typically need:

```text
fullchain.pem
privkey.pem
```

Do not copy the private key casually into multiple locations.

---

# Phase 13 — Test Renewal Against Staging

Run:

```bash
sudo docker run --rm \
  -v /opt/acme/etc:/etc/letsencrypt \
  -v /opt/acme/lib:/var/lib/letsencrypt \
  -v /opt/acme/log:/var/log/letsencrypt \
  -v /opt/acme/credentials:/root/.secrets:ro \
  certbot/dns-cloudflare:latest \
  renew \
  --dry-run
```

The dry run must succeed before moving to production issuance.

---

# Phase 14 — Issue the Production Certificate

Once staging and renewal tests succeed, remove `--staging` and issue the real certificate.

```bash
sudo docker run --rm \
  -v /opt/acme/etc:/etc/letsencrypt \
  -v /opt/acme/lib:/var/lib/letsencrypt \
  -v /opt/acme/log:/var/log/letsencrypt \
  -v /opt/acme/credentials:/root/.secrets:ro \
  certbot/dns-cloudflare:latest \
  certonly \
  --dns-cloudflare \
  --dns-cloudflare-credentials /root/.secrets/cloudflare.ini \
  --dns-cloudflare-propagation-seconds 30 \
  --non-interactive \
  --agree-tos \
  --email YOUR_EMAIL_ADDRESS \
  -d atreides.lan.rirl.dev
```

Verify again:

```bash
sudo docker run --rm \
  -v /opt/acme/etc:/etc/letsencrypt \
  -v /opt/acme/lib:/var/lib/letsencrypt \
  -v /opt/acme/log:/var/log/letsencrypt \
  certbot/dns-cloudflare:latest \
  certificates
```

---

# Phase 15 — Verify the Production Certificate with OpenSSL

Inspect the certificate directly:

```bash
sudo openssl x509 \
  -in /opt/acme/etc/live/atreides.lan.rirl.dev/fullchain.pem \
  -noout \
  -subject \
  -issuer \
  -dates \
  -ext subjectAltName
```

Expected SAN:

```text
DNS:atreides.lan.rirl.dev
```

The issuer should be Let's Encrypt rather than the staging CA.

---

# Phase 16 — Add Automated Renewal

Certbot certificates are intentionally short-lived, so renewal must be automated.

Create a small host-side renewal script:

```bash
sudo vi /usr/local/sbin/renew-letsencrypt-docker
```

Contents:

```bash
#!/usr/bin/env bash
set -euo pipefail

IMAGE="certbot/dns-cloudflare:latest"

/usr/bin/docker pull "$IMAGE"

/usr/bin/docker run --rm \
  -v /opt/acme/etc:/etc/letsencrypt \
  -v /opt/acme/lib:/var/lib/letsencrypt \
  -v /opt/acme/log:/var/log/letsencrypt \
  -v /opt/acme/credentials:/root/.secrets:ro \
  "$IMAGE" \
  renew
```

Protect it:

```bash
sudo chown root:root /usr/local/sbin/renew-letsencrypt-docker
sudo chmod 755 /usr/local/sbin/renew-letsencrypt-docker
```

Test it manually:

```bash
sudo /usr/local/sbin/renew-letsencrypt-docker
```

---

# Phase 17 — Create a systemd Renewal Service

Create:

```bash
sudo vi /etc/systemd/system/letsencrypt-docker-renew.service
```

Contents:

```ini
[Unit]
Description=Renew Let's Encrypt certificates using Dockerized Certbot
Requires=docker.service
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/renew-letsencrypt-docker
```

---

# Phase 18 — Create a systemd Timer

Create:

```bash
sudo vi /etc/systemd/system/letsencrypt-docker-renew.timer
```

Contents:

```ini
[Unit]
Description=Check Let's Encrypt certificate renewal twice daily

[Timer]
OnCalendar=*-*-* 03,15:17:00
RandomizedDelaySec=30m
Persistent=true

[Install]
WantedBy=timers.target
```

Reload systemd:

```bash
sudo systemctl daemon-reload
```

Enable the timer:

```bash
sudo systemctl enable --now letsencrypt-docker-renew.timer
```

Verify:

```bash
systemctl list-timers --all | grep letsencrypt
```

Inspect status:

```bash
systemctl status letsencrypt-docker-renew.timer
```

Run the service immediately as a test:

```bash
sudo systemctl start letsencrypt-docker-renew.service
```

Inspect logs:

```bash
journalctl -u letsencrypt-docker-renew.service --no-pager
```

---

# Phase 19 — Decide Whether to Introduce a Wildcard

Do not start with a wildcard unless you need it.

After the single-name workflow is proven, you can optionally request:

```text
atreides.lan.rirl.dev
*.atreides.lan.rirl.dev
```

Example:

```bash
sudo docker run --rm \
  -v /opt/acme/etc:/etc/letsencrypt \
  -v /opt/acme/lib:/var/lib/letsencrypt \
  -v /opt/acme/log:/var/log/letsencrypt \
  -v /opt/acme/credentials:/root/.secrets:ro \
  certbot/dns-cloudflare:latest \
  certonly \
  --dns-cloudflare \
  --dns-cloudflare-credentials /root/.secrets/cloudflare.ini \
  --dns-cloudflare-propagation-seconds 30 \
  --non-interactive \
  --agree-tos \
  --email YOUR_EMAIL_ADDRESS \
  -d atreides.lan.rirl.dev \
  -d '*.atreides.lan.rirl.dev'
```

This would support names such as:

```text
openwebui.atreides.lan.rirl.dev
ollama.atreides.lan.rirl.dev
mcp.atreides.lan.rirl.dev
```

Keep in mind that a wildcard private key is more sensitive because it can authenticate multiple services.

---

# Phase 20 — LAN Name Resolution

Before consuming the certificate from local tools, make sure your client machines resolve:

```text
atreides.lan.rirl.dev
```

to the Ubuntu host's LAN address.

You may do this through:

- router-local DNS
- Pi-hole / AdGuard Home / dnsmasq / Unbound
- another internal DNS service
- temporary `/etc/hosts` or Windows `hosts` entries during testing

Temporary Ubuntu test example:

```text
192.168.1.x atreides.lan.rirl.dev
```

Temporary Windows test entry would later go in:

```text
C:\Windows\System32\drivers\etc\hosts
```

Do not rely on `.local` for HTTPS certificate hostname verification when the certificate is issued to `atreides.lan.rirl.dev`.

---

# Phase 21 — Validate with a Local HTTPS Service

Before integrating with a production local tool, it is useful to test the certificate with a minimal HTTPS endpoint.

For example, use nginx or another local container that mounts:

```text
/opt/acme/etc/live/atreides.lan.rirl.dev/fullchain.pem
/opt/acme/etc/live/atreides.lan.rirl.dev/privkey.pem
```

Then browse to:

```text
https://atreides.lan.rirl.dev
```

The browser should show a publicly trusted Let's Encrypt certificate, provided the name resolves to the Ubuntu host and the service presents the correct certificate.

---

# Phase 22 — Renewal Hooks for Real Services

Once a real service consumes the certificate, certificate renewal alone is not enough if the service caches TLS material.

You may need a deploy hook that performs one of the following after successful renewal:

```text
reload nginx
restart/reload reverse proxy
restart a specific container
signal a daemon to reload certificates
```

Do not add a restart hook until the consuming service is identified.

The renewal mechanism should first be proven independently.

---

# Phase 23 — Ubuntu Completion Criteria

Do not begin the Windows phase until all of the following are true.

- [ ] `lan.rirl.dev` is delegated to Cloudflare.
- [ ] `dig NS lan.rirl.dev` shows Cloudflare authority.
- [ ] A restricted Cloudflare API token exists.
- [ ] The token is stored only in `/opt/acme/credentials/cloudflare.ini` with mode `600`.
- [ ] `certbot/dns-cloudflare:latest` runs successfully in Docker.
- [ ] A Let's Encrypt staging certificate was issued successfully.
- [ ] `renew --dry-run` succeeds.
- [ ] A production certificate for `atreides.lan.rirl.dev` was issued successfully.
- [ ] OpenSSL shows the expected SAN and Let's Encrypt issuer.
- [ ] The systemd renewal timer is enabled.
- [ ] A manual systemd renewal service run succeeds.
- [ ] `atreides.lan.rirl.dev` resolves correctly on the LAN.
- [ ] At least one local HTTPS service successfully presents the certificate.

At that point the Ubuntu side is considered proven.

---

# Windows Phase — Deferred

Do not perform these steps yet.

When Ubuntu is complete, the next phase will address booting the same physical machine into Windows and deciding how to handle:

- Windows-side certificate storage
- whether Windows obtains its own certificate independently
- whether the Cloudflare token should be separately scoped/stored
- Docker Desktop versus another ACME runtime
- certificate renewal scheduling under Windows
- service-specific certificate deployment
- private-key separation between the Ubuntu and Windows installations
- whether the same FQDN should identify both OS personalities of the same physical host

A particularly important design question for the Windows phase will be whether:

```text
atreides.lan.rirl.dev
```

should refer to the physical machine regardless of which OS is booted, or whether OS-specific names such as:

```text
ubuntu.atreides.lan.rirl.dev
windows.atreides.lan.rirl.dev
```

provide cleaner key and certificate separation.

That decision is intentionally deferred until the Ubuntu automation is working.

---

# Useful Diagnostic Commands

## DNS delegation

```bash
dig NS lan.rirl.dev
```

```bash
dig +trace NS lan.rirl.dev
```

## ACME TXT record

During a challenge, inspect:

```bash
dig TXT _acme-challenge.atreides.lan.rirl.dev
```

## Certbot version

```bash
sudo docker run --rm certbot/dns-cloudflare:latest --version
```

## Installed Certbot plugins

```bash
sudo docker run --rm certbot/dns-cloudflare:latest plugins
```

## Certificate inventory

```bash
sudo docker run --rm \
  -v /opt/acme/etc:/etc/letsencrypt \
  -v /opt/acme/lib:/var/lib/letsencrypt \
  -v /opt/acme/log:/var/log/letsencrypt \
  certbot/dns-cloudflare:latest \
  certificates
```

## Renewal dry run

```bash
sudo docker run --rm \
  -v /opt/acme/etc:/etc/letsencrypt \
  -v /opt/acme/lib:/var/lib/letsencrypt \
  -v /opt/acme/log:/var/log/letsencrypt \
  -v /opt/acme/credentials:/root/.secrets:ro \
  certbot/dns-cloudflare:latest \
  renew \
  --dry-run
```

## Certificate inspection

```bash
sudo openssl x509 \
  -in /opt/acme/etc/live/atreides.lan.rirl.dev/fullchain.pem \
  -noout \
  -subject \
  -issuer \
  -dates \
  -ext subjectAltName
```

## Renewal timer

```bash
systemctl status letsencrypt-docker-renew.timer
```

```bash
systemctl list-timers --all | grep letsencrypt
```

## Renewal logs

```bash
journalctl -u letsencrypt-docker-renew.service --no-pager
```

---

# Security Notes

1. Keep the Cloudflare token scoped to the smallest possible zone and permissions.
2. Never use the legacy Global API Key for this workflow unless there is no alternative.
3. Keep `cloudflare.ini` mode `600` and root-owned.
4. Do not commit `/opt/acme` or token files to Git.
5. Keep private keys host-local whenever practical.
6. Do not expose LAN services publicly merely to satisfy ACME; DNS-01 removes that requirement.
7. Test against Let's Encrypt staging before production issuance.
8. Record the Docker image digest used for successful issuance if reproducibility matters.
9. Treat wildcard private keys as higher-value secrets than single-host certificates.

---

# Current Reference Notes

As of August 2026:

- the official Docker image for Certbot with the Cloudflare DNS plugin is `certbot/dns-cloudflare`;
- Cloudflare recommends scoped API tokens over legacy API keys where possible;
- Squarespace documents subdomain NS delegation and currently notes that DNSSEC must be disabled before adding NS records to a subdomain;
- Cloudflare's normal full-zone configuration is authoritative DNS, but this guide intentionally uses the narrower `lan.rirl.dev` delegation boundary instead of moving all of `rirl.dev`.

