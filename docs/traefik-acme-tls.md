# Traefik + Let's Encrypt TLS Setup

## The Problem

Let's Encrypt uses the **HTTP-01 challenge** to verify domain ownership before issuing a certificate. It works like this:

1. Let's Encrypt sends an HTTP request to `http://your-domain/.well-known/acme-challenge/<token>`
2. Your server must respond correctly over **port 80**
3. If port 80 is unreachable → `Connection refused` → certificate issuance fails

The original `docker-compose.yml` only defined the `websecure` (port 443) entrypoint for the webhook router. Traefik had no HTTP router to handle port 80 traffic, so Let's Encrypt's challenge requests were refused.

**Error seen in logs:**
```
Unable to obtain ACME certificate for domains error="...
[webhook-site.smartlayer.dev] invalid authorization: acme: error: 400 ::
urn:ietf:params:acme:error:connection :: 51.158.76.187: Connection refused"
```

## The Fix

Add an HTTP (`web`) router to the service labels so Traefik listens on port 80 for the domain. That router redirects all traffic to HTTPS, satisfying both the ACME challenge and security best practice.

```yaml
labels:
  - "traefik.enable=true"

  # HTTPS router
  - "traefik.http.routers.webhook-site.rule=Host(`webhook-site.smartlayer.dev`)"
  - "traefik.http.routers.webhook-site.entrypoints=websecure"
  - "traefik.http.routers.webhook-site.tls.certresolver=letsencrypt"
  - "traefik.http.services.webhook-site.loadbalancer.server.port=80"

  # HTTP router (required for ACME HTTP-01 challenge)
  - "traefik.http.routers.webhook-site-http.rule=Host(`webhook-site.smartlayer.dev`)"
  - "traefik.http.routers.webhook-site-http.entrypoints=web"
  - "traefik.http.routers.webhook-site-http.middlewares=redirect-to-https"

  # Redirect middleware
  - "traefik.http.middlewares.redirect-to-https.redirectscheme.scheme=https"
  - "traefik.http.middlewares.redirect-to-https.redirectscheme.permanent=true"
```

## Prerequisites on the Traefik Host

### 1. Traefik must expose port 80

In Traefik's own `docker-compose.yml`:
```yaml
ports:
  - "80:80"
  - "443:443"
```

### 2. Traefik must have a `web` entrypoint defined

In `traefik.yml` (or equivalent static config):
```yaml
entryPoints:
  web:
    address: ":80"
  websecure:
    address: ":443"

certificatesResolvers:
  letsencrypt:
    acme:
      email: your@email.com
      storage: /letsencrypt/acme.json
      httpChallenge:
        entryPoint: web
```

### 3. Firewall must allow inbound TCP port 80

Let's Encrypt's servers must be able to reach your server on port 80 from the public internet. Check your cloud provider's security group / firewall rules and ensure port 80 is open to `0.0.0.0/0`.

## How the Certificate Renewal Flow Works

```
Let's Encrypt  ──HTTP GET:80──▶  Traefik (web entrypoint)
                                      │
                                      │ matches /.well-known/acme-challenge/*
                                      │ Traefik handles challenge internally
                                      ▼
                               Certificate issued & stored in acme.json
                                      │
                                      ▼
                  All other HTTP traffic → 301 redirect → HTTPS
```

Traefik automatically renews certificates before expiry (~30 days before). As long as port 80 remains reachable, renewals are fully automatic.
