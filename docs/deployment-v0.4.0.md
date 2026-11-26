# AINotify v0.4.0 Deployment, Maintenance and Recovery Guide

This guide describes self-hosted HTTPS deployment, reverse proxy setup, automated TLS certificate renewal, SQLite consistency backup/restore, credential rotation, and rollback procedures for AINotify v0.4.0.

---

## 1. Production HTTPS Reverse Proxy Setup

The AINotify Relay (`ai-notify-relay`) binds to a local TCP interface (`127.0.0.1:8787` by default). In production, place it behind an HTTPS reverse proxy with automatic ACME TLS certificate management.

### Option A: Caddy (Recommended)

Caddy automatically provisions and renews Let's Encrypt / ZeroSSL TLS certificates with zero maintenance.

```caddyfile
# /etc/caddy/Caddyfile
relay.example.com {
    # Automatic TLS with Let's Encrypt / ZeroSSL
    tls admin@example.com

    # Security Headers
    header {
        Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
        X-Content-Type-Options "nosniff"
        X-Frame-Options "DENY"
        Referrer-Policy "no-referrer"
    }

    # Proxy to local Relay daemon
    reverse_proxy 127.0.0.1:8787 {
        header_up Host {host}
        header_up X-Real-IP {remote_host}
        header_up X-Forwarded-For {remote_host}
        header_up X-Forwarded-Proto {scheme}
    }

    # Health check logging level
    log {
        output file /var/log/caddy/ainotify-access.log
    }
}
```

### Option B: Nginx + Certbot

```nginx
# /etc/nginx/sites-available/ainotify
server {
    listen 80;
    server_name relay.example.com;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl http2;
    server_name relay.example.com;

    ssl_certificate /etc/letsencrypt/live/relay.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/relay.example.com/privkey.pem;
    include /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;

    # Payload size limit matching Relay 820KB limit
    client_max_body_size 1m;

    location / {
        proxy_pass http://127.0.0.1:8787;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

Certbot renewal cron/timer:
`certbot renew --quiet --deploy-hook "systemctl reload nginx"`

---

## 2. Health Monitoring & Diagnostic Endpoints

- **Unauthenticated Health Probe**: `GET /healthz` returns `{"ok": true}` with HTTP 200. Suitable for external uptime monitors (Uptime Kuma, AWS Route53 health checks, Kubernetes probes) without leaking database statistics or private credentials.
- **Collector Authorization Probe**: `GET /v1/writer/status` with `Authorization: Bearer <writer_token>` returns `{"device_id": "<id>"}` confirming writer credential validity and device identity assignment.
- **Client Synchronization Status**: Clients report connected state and connection icons in UI based on authenticated `GET /v1/events` heartbeat.

---

## 3. SQLite Database Consistency Backup and Pruning

`ai-notify-relay` uses SQLite in WAL (`Write-Ahead Logging`) mode. Direct file copying while the daemon is actively writing can result in partial or torn reads.

### Online Consistency Backup

The Relay supports SQLite online atomic snapshots using `VACUUM INTO` or the SQLite Online Backup API. This produces a compacted, consistent database file without interrupting active HTTP requests:

```sh
# Trigger an online consistency snapshot
ai-notify-relay backup --db /var/lib/ainotify/ainotify.sqlite3 --output /var/backups/ainotify/backup-$(date +%Y%m%d%H%M%S).sqlite3
```

Automated daily backup cron (`/etc/cron.daily/ainotify-backup`):
```sh
#!/usr/bin/env bash
set -euo pipefail
BACKUP_DIR="/var/backups/ainotify"
mkdir -p "${BACKUP_DIR}"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
ai-notify-relay backup --db /var/lib/ainotify/ainotify.sqlite3 --output "${BACKUP_DIR}/ainotify-${TIMESTAMP}.sqlite3"
# Keep 14 days of snapshots
find "${BACKUP_DIR}" -name "ainotify-*.sqlite3" -mtime +14 -delete
```

### Event Retention & Pruning Policy

To prevent unbounded SQLite disk growth, events can be pruned based on age or maximum count:

```sh
# Prune events older than 30 days
ai-notify-relay prune --db /var/lib/ainotify/ainotify.sqlite3 --older-than-days 30

# Keep only the last 10,000 events
ai-notify-relay prune --db /var/lib/ainotify/ainotify.sqlite3 --keep-last 10000
```
Pruning also purges associated orphaned `push_deliveries` entries.

---

## 4. Disaster Recovery, Snapshot Rollback & Stream ID Strategy

When restoring from a backup, the event sequence and stream identity contract dictates client behavior:

1. **In-place Restore without Rewind (Direct Recovery)**:
   - If restoring the database to a fresh machine or replacing corrupted storage where the backup is the direct ancestor of current state:
   - Preserve the database `stream_id`.
   - Existing connected clients (Android phone, Wear OS watch) continue fetching from their last saved cursor without resetting.

2. **Snapshot Rollback (Rewinding to an Older State)**:
   - If rolling back to an older backup snapshot where recent events were lost:
   - The Relay's sequence numbers may conflict or rewind.
   - Run restore with stream ID regeneration:
     ```sh
     ai-notify-relay restore --input /var/backups/ainotify/backup-yesterday.sqlite3 --db /var/lib/ainotify/ainotify.sqlite3 --reset-stream-id
     ```
   - **Client Behavior**: When clients query `GET /v1/events?stream_id=<old_stream_id>&after=<cursor>`, the Relay detects the stream ID mismatch, returns `reset_cursor: true`, and provides events from sequence 0.
   - The clients reset their local cursors, re-pull all available events from sequence 0, and deduplicate against existing local records by UUID.
   - No duplicates are posted; no missed notifications occur.

---

## 5. Zero-Downtime Credential Rotation

AINotify supports zero-downtime credential rotation for `reader`, `inbox`, and `writer` credentials.

### Reader & Inbox Token Rotation

The Relay accepts comma-separated tokens in `AINOTIFY_READER_TOKEN` and `AINOTIFY_INBOX_TOKEN`.

1. **Phase 1 (Dual-Key Acceptance)**:
   Generate a new token: `NEW_READER=$(openssl rand -hex 32)`
   Update Relay environment:
   ```env
   AINOTIFY_READER_TOKEN="<OLD_TOKEN>,<NEW_TOKEN>"
   ```
   Reload Relay: `systemctl restart ai-notify-relay`. Because Relay loads configuration from environment variables at startup, restarting the service (< 100ms) loads the updated token set. Both tokens are now valid in parallel, guaranteeing zero client disruption during migration.

2. **Phase 2 (Client Migration)**:
   Update the phone and watch settings to `<NEW_TOKEN>` via the Settings UI or profile settings file.

3. **Phase 3 (Revocation of Old Token)**:
   Update Relay environment to remove `<OLD_TOKEN>`:
   ```env
   AINOTIFY_READER_TOKEN="<NEW_TOKEN>"
   ```
   Restart Relay: `systemctl restart ai-notify-relay`. `<OLD_TOKEN>` is permanently revoked.

### Writer Token Rotation

For collector devices (`ai-notify-agent`), `AINOTIFY_WRITERS` is configured as a JSON object mapping device names to token strings or arrays of tokens. Follow the same multi-token phase-in, re-configure the agent with `ai-notify-agent configure`, and revoke the previous token.
