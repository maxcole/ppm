---
---

# Plan 03 — Starter Service Repository

## Context — read these files first

- `lib/services/service.sh` — `profile_install()`, how services are installed (plan 01)
- `lib/services/compose.sh` — `_build_env_file()`, env var injection, `_compose_run()` (plan 01)
- `lib/services/network.sh` — `_resolve_network()`, `PSM_NETWORK` variable (plan 01)
- Old PSM script: `~/.local/share/psm/psm/psm` — `cmd_registry_add()` for the scaffold template
- `packages/psm/install.sh` — where psm sources.list is bootstrapped (platform plan 03)

## Overview

Create the `psm-ppm` service repository with a working `postgres` service definition and a `gatekeeper` meta-service that demonstrates dependency chains and network isolation. Update the `psm` package's install hook to add `psm-ppm` as a default source.

After this plan, a fresh `ppm install psm && psm update && psm install postgres && psm up postgres` gives you a running PostgreSQL instance.

## Implementation

### 1. Create the `psm-ppm` repository

Initialize a new git repo at `~/.local/share/psm/psm-ppm/` (this will be the canonical location after `psm update` clones it).

For development, create it locally. It will be pushed to a remote (e.g., GitHub) separately.

### 2. Create `services/postgres/`

```
services/postgres/
  package.yml
  service.sh
  compose.yml
  .env.example
  .schema.env
  psm.yml
  pcm.yml
```

#### `package.yml`

```yaml
version: 0.1.0
author: rjayroach
```

No dependencies — postgres is a leaf service.

#### `compose.yml`

```yaml
services:
  postgres:
    image: docker.io/library/postgres:16-alpine
    container_name: ${PSM_NETWORK}-postgres
    restart: unless-stopped
    environment:
      POSTGRES_USER: ${POSTGRES_USER:-postgres}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:-postgres}
      POSTGRES_DB: ${POSTGRES_DB:-postgres}
    volumes:
      - ${PSM_DATA}:/var/lib/postgresql/data
    ports:
      - "${POSTGRES_PORT:-5432}:5432"
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER:-postgres}"]
      interval: 10s
      timeout: 5s
      retries: 5

networks:
  default:
    external: true
    name: ${PSM_NETWORK}
```

#### `.env.example`

```bash
POSTGRES_USER=postgres
POSTGRES_PASSWORD=postgres
POSTGRES_DB=postgres
POSTGRES_PORT=5432
```

#### `.schema.env`

```bash
# @defaultRequired=false
#
# PSM-provided (do not set manually):
#   PSM_DATA, PSM_CONFIG, PSM_CACHE, PSM_SERVICE, PSM_NETWORK, PSM_TYPE
#
# POSTGRES_USER     — Database superuser name
# @default postgres
POSTGRES_USER=

# POSTGRES_PASSWORD — Database superuser password
# @default postgres
# @secret
POSTGRES_PASSWORD=

# POSTGRES_DB       — Default database name
# @default postgres
POSTGRES_DB=

# POSTGRES_PORT     — Host port mapping
# @default 5432
POSTGRES_PORT=
```

#### `psm.yml`

```yaml
name: postgres
description: PostgreSQL 16 relational database
ports:
  - "5432 (configurable via POSTGRES_PORT)"
```

#### `pcm.yml`

```yaml
# PCM credential definitions for postgres
# Used when varlock + PCM are installed
credentials:
  postgres_password:
    description: PostgreSQL superuser password
    env_var: POSTGRES_PASSWORD
    vault_key: psm/postgres/password
```

#### `service.sh`

```bash
#!/usr/bin/env bash
# Postgres service hooks

pre_install() {
  debug "Preparing postgres data directory"
}

post_install() {
  user_message "PostgreSQL ready. Start with: psm up postgres"
  user_message "Default credentials: postgres/postgres (override in config/.env)"
}
```

### 3. Create `services/redis/`

Minimal Redis service as a second leaf dependency.

#### `package.yml`

```yaml
version: 0.1.0
author: rjayroach
```

#### `compose.yml`

```yaml
services:
  redis:
    image: docker.io/library/redis:7-alpine
    container_name: ${PSM_NETWORK}-redis
    restart: unless-stopped
    command: redis-server --appendonly yes
    volumes:
      - ${PSM_DATA}:/data
    ports:
      - "${REDIS_PORT:-6379}:6379"
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5

networks:
  default:
    external: true
    name: ${PSM_NETWORK}
```

#### `.env.example`

```bash
REDIS_PORT=6379
```

#### `psm.yml`

```yaml
name: redis
description: Redis 7 in-memory data store
ports:
  - "6379 (configurable via REDIS_PORT)"
```

#### `service.sh`

```bash
#!/usr/bin/env bash
post_install() {
  user_message "Redis ready. Start with: psm up redis"
}
```

### 4. Create `services/gatekeeper/`

Meta-service demonstrating dependency chains and network isolation.

#### `package.yml`

```yaml
version: 0.1.0
author: rjayroach
depends:
  - postgres
  - redis
network: gatekeeper
```

No compose.yml — gatekeeper is a dependency bundle. Its value is pulling in postgres and redis onto an isolated network.

#### `psm.yml`

```yaml
name: gatekeeper
description: Auth + user management stack (postgres + redis on isolated network)
```

#### `service.sh`

```bash
#!/usr/bin/env bash
post_install() {
  user_message "Gatekeeper stack installed on isolated 'gatekeeper' network"
  user_message "Includes: postgres, redis"
  user_message "Start with: psm up gatekeeper"
}
```

### 5. Update the psm package to include default source

Modify `packages/psm/install.sh` to add the psm-ppm source to the default `sources.list`:

```bash
post_install() {
  local psm_config="${XDG_CONFIG_HOME:-$HOME/.config}/psm"
  local psm_data="${XDG_DATA_HOME:-$HOME/.local/share}/psm"

  mkdir -p "$psm_config"
  mkdir -p "$psm_data/services"

  # Create default sources.list with psm-ppm if it doesn't exist
  if [[ ! -f "$psm_config/sources.list" ]]; then
    cat > "$psm_config/sources.list" <<'EOF'
https://github.com/maxcole/psm-ppm  psm-ppm
EOF
    user_message "Created $psm_config/sources.list with default service source"
    user_message "Run: psm update  to fetch service definitions"
  fi
}
```

Note: The remote URL (`maxcole/psm-ppm` or whatever the canonical org is) should be confirmed before pushing. For local development, the source can be a local path added manually via `psm src add /path/to/psm-ppm`.

### 6. Create a README for psm-ppm

```markdown
# PSM Service Repository

Service definitions for PSM (Podman Service Manager).

## Available Services

| Service     | Description                            | Dependencies      |
|-------------|----------------------------------------|--------------------|
| postgres    | PostgreSQL 16 relational database      | none               |
| redis       | Redis 7 in-memory data store           | none               |
| gatekeeper  | Auth + user management stack           | postgres, redis    |

## Usage

```bash
psm src add https://github.com/maxcole/psm-ppm
psm update
psm install postgres
psm up postgres
```

## Service Structure

Each service directory contains:

| File            | Purpose                                    | Required |
|-----------------|--------------------------------------------|----------|
| `package.yml`   | Version, dependencies, network scope       | yes      |
| `compose.yml`   | Compose spec (uses PSM env vars)           | no *     |
| `.env.example`  | Default env vars (no PCM needed)           | yes      |
| `.schema.env`   | Varlock schema for validation              | yes      |
| `psm.yml`       | Service metadata (name, description)       | yes      |
| `pcm.yml`       | PCM credential definitions                 | no       |
| `service.sh`    | Lifecycle hooks (pre/post install/remove)  | no       |

\* Meta-services (dependency bundles) may omit compose.yml
```

## Test Spec

### Postgres end-to-end

```bash
psm src add /path/to/psm-ppm test-services
psm update
psm list                     # shows postgres, redis, gatekeeper
psm install postgres
psm up postgres
psm status                   # postgres running on psm network
psm logs postgres            # shows postgres startup logs
psm down postgres
```

### Gatekeeper dependency chain

```bash
psm install gatekeeper
# Should install postgres and redis on gatekeeper network, then gatekeeper itself
ls ~/.local/share/psm/services/gatekeeper/
# Should contain: postgres/ redis/ gatekeeper/

psm up gatekeeper
psm status
# Should show postgres, redis under gatekeeper network

psm down gatekeeper
# Should stop redis, postgres in reverse order
```

### Network isolation

```bash
# Install postgres standalone (psm network) AND via gatekeeper (gatekeeper network)
psm install postgres         # → services/psm/postgres/
psm install gatekeeper       # → services/gatekeeper/postgres/ (separate instance)

psm up postgres
psm up gatekeeper

psm status
# Should show:
#   psm:
#     postgres    running
#   gatekeeper:
#     postgres    running
#     redis       running

# Two separate postgres containers, different data dirs, different networks
podman ps | grep postgres    # should show 2 containers
```

## Verification

- [ ] `psm-ppm` repo exists with `services/postgres/`, `services/redis/`, `services/gatekeeper/`
- [ ] Each service has `package.yml`, `compose.yml` (where applicable), `.env.example`, `psm.yml`
- [ ] `psm install postgres` creates correct directory structure
- [ ] `psm up postgres` starts a running PostgreSQL container
- [ ] `psm logs postgres` shows PostgreSQL startup output
- [ ] `psm down postgres` stops the container
- [ ] `psm install gatekeeper` resolves postgres + redis deps onto gatekeeper network
- [ ] `psm up gatekeeper` starts postgres then redis in order
- [ ] `psm down gatekeeper` stops in reverse order
- [ ] Two postgres instances can run simultaneously on different networks
- [ ] `psm list` shows all three services
- [ ] `psm show postgres` shows metadata and install status
