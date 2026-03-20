---
---

# Plan 01 — Service Backend Libraries

## Context — read these files first

- `lib/packages/stow.sh` — reference implementation: `profile_install()` and `profile_remove()` for the package backend
- `lib/installer.sh` — generic installer/remover that calls `profile_install()`/`profile_remove()`
- `ppm` — main script bootstrap: env var setup, backend lib sourcing from `lib/$PPM_ASSET_DIR/`
- `docs/adr/001-ppm-as-configurable-engine.md` — architectural context, especially the network model
- Old PSM script (reference, not in repo): `~/.local/share/psm/psm/psm` — `_compose_run()`, `_build_env_file()`, `_ensure_psm_network()`, scope resolution, service directory helpers

## Overview

Create the service backend libraries in `lib/services/`. These define `profile_install()` and `profile_remove()` for service assets, plus the PSM-specific helpers: scope resolution, Podman network management, compose runner with varlock integration, and env var injection.

After this plan, `psm install postgres` works end-to-end (given a service definition exists in a source repo). Lifecycle commands (up, down, etc.) come in plan 02.

## Implementation

### 1. Create `lib/services/scope.sh`

Handles user/system scope resolution. PSM adds `--user`/`--system` flags to the global flag parser. These are only relevant when the service backend is loaded.

```bash
#!/usr/bin/env bash
# Service backend — scope resolution (user vs system)

# Parse PSM-specific flags from global args
# Called during engine bootstrap if service backend is loaded
PSM_SCOPE_OVERRIDE=""
PSM_SKIP_VALIDATION="${PSM_SKIP_VALIDATION:-}"

# Note: flag parsing happens in the main ppm script's flag loop.
# The service backend registers additional flags by exporting a
# parse_backend_flag() function that the main script calls for
# unrecognized flags.

parse_backend_flag() {
  case "$1" in
    --user)               PSM_SCOPE_OVERRIDE="user"; return 0 ;;
    --system)             PSM_SCOPE_OVERRIDE="system"; return 0 ;;
    -s|--skip-validation) PSM_SKIP_VALIDATION=1; return 0 ;;
    *)                    return 1 ;;
  esac
}

# Resolve scope after config is loaded
# Call this after config file is read but before any service operations
_resolve_scope() {
  local config_scope=""
  if [[ -f "$PPM_CONFIG_HOME/psm.conf" ]]; then
    config_scope=$(grep -E '^scope=' "$PPM_CONFIG_HOME/psm.conf" 2>/dev/null | cut -d= -f2)
  fi

  PSM_SCOPE="${PSM_SCOPE_OVERRIDE:-${config_scope:-user}}"

  case "$PSM_SCOPE" in
    user)
      PSM_HOME="$PPM_DATA_HOME"
      ;;
    system)
      PSM_HOME="/opt/psm"
      ;;
    *)
      echo "psm: Invalid scope: ${PSM_SCOPE} (must be 'user' or 'system')" >&2
      exit 1
      ;;
  esac

  PSM_SERVICES_HOME="${PSM_HOME}/services"
}

# Auto-resolve on source (service backend is only loaded when PSM env vars are set)
_resolve_scope
```

### 2. Create `lib/services/network.sh`

Manages Podman network creation and resolution.

```bash
#!/usr/bin/env bash
# Service backend — Podman network management

# Default network name
PSM_DEFAULT_NETWORK="psm"

# Ensure a named Podman network exists
# Usage: _ensure_network <network_name>
_ensure_network() {
  local network="${1:-$PSM_DEFAULT_NETWORK}"
  if ! podman network exists "$network" 2>/dev/null; then
    debug "Creating Podman network: $network"
    podman network create "$network" >/dev/null
  fi
}

# Read the network key from a service's package.yml
# Returns the network name or empty string for default
# Usage: _service_network <asset_dir>
_service_network() {
  local asset_dir="$1"
  local meta="$asset_dir/package.yml"
  [[ -f "$meta" ]] || return 0
  local net
  net=$(yq -r '.network // ""' "$meta" 2>/dev/null)
  [[ "$net" == "null" ]] && net=""
  echo "$net"
}

# Resolve the effective network for a service
# If the service declares a network, use it. Otherwise use the context
# network (passed during dep resolution) or fall back to default.
# Usage: _resolve_network <asset_dir> [context_network]
_resolve_network() {
  local asset_dir="$1" context="${2:-}"
  local declared
  declared=$(_service_network "$asset_dir")

  if [[ -n "$declared" ]]; then
    echo "$declared"
  elif [[ -n "$context" ]]; then
    echo "$context"
  else
    echo "$PSM_DEFAULT_NETWORK"
  fi
}
```

### 3. Create `lib/services/compose.sh`

Compose runner with env injection and varlock integration. Ported from the old PSM script's `_compose_run()` and `_build_env_file()`.

```bash
#!/usr/bin/env bash
# Service backend — compose runner and env injection

_require_podman() {
  for cmd in podman podman-compose; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      echo "psm: '$cmd' is not installed" >&2
      exit 1
    fi
  done
}

# Build a temporary env file for a service instance
# Usage: _build_env_file <service_name> <instance_dir> <registry_dir> <network>
_build_env_file() {
  local service="$1" instance_dir="$2" registry_dir="$3" network="$4"

  local env_file
  env_file=$(mktemp /tmp/psm-env.XXXXXX)

  # PSM-provided variables
  cat > "$env_file" <<EOF
PSM_DATA=${instance_dir}/data
PSM_CONFIG=${instance_dir}/config
PSM_CACHE=${PPM_CACHE_HOME:-$HOME/.cache/psm}/services/${network}/${service}
PSM_SERVICE=${service}
PSM_NETWORK=${network}
PSM_TYPE=${PSM_SCOPE}
EOF

  # Registry .env.example defaults
  local example_env="${registry_dir}/.env.example"
  [[ -f "$example_env" ]] && cat "$example_env" >> "$env_file"

  # User overrides
  local user_env="${instance_dir}/config/.env"
  [[ -f "$user_env" ]] && cat "$user_env" >> "$env_file"

  echo "$env_file"
}

# Find the compose file in a registry directory
# Usage: _find_compose_file <registry_dir>
_find_compose_file() {
  local dir="$1"
  for name in compose.yml compose.yaml docker-compose.yml docker-compose.yaml; do
    if [[ -f "${dir}/${name}" ]]; then
      echo "${dir}/${name}"
      return
    fi
  done
  echo "psm: No compose file found in ${dir}" >&2
  return 1
}

# Run a compose command for a service instance
# Usage: _compose_run <service_name> <network> <compose_args...>
_compose_run() {
  local service="$1" network="$2"
  shift 2

  _require_podman
  _ensure_network "$network"

  local instance_dir="${PSM_SERVICES_HOME}/${network}/${service}"
  local registry_dir="${instance_dir}/registry"

  if [[ ! -L "$registry_dir" && ! -d "$registry_dir" ]]; then
    echo "psm: Service '${service}' is not installed on network '${network}'. Run: psm install ${service}" >&2
    return 1
  fi

  local compose_file
  compose_file=$(_find_compose_file "$registry_dir") || return 1

  local schema_env="${registry_dir}/.schema.env"
  local env_file
  env_file=$(_build_env_file "$service" "$instance_dir" "$registry_dir" "$network")

  local project_name="${network}-${service}"

  # Varlock path: validate schema + resolve credentials, then run compose
  if [[ -z "${PSM_SKIP_VALIDATION:-}" ]] \
     && command -v varlock >/dev/null 2>&1 \
     && [[ -f "$schema_env" ]]; then
    debug "varlock detected — using validated env from .schema.env"

    (
      cd "$registry_dir"
      varlock run -- podman-compose \
        -f "$compose_file" \
        --env-file "$env_file" \
        -p "$project_name" \
        "$@"
    )
    local ret=$?
    rm -f "$env_file"
    return $ret
  fi

  # Simple path: env from .env.example + user overrides
  if [[ -n "${PSM_SKIP_VALIDATION:-}" ]]; then
    debug "Validation skipped (-s)"
  else
    debug "No varlock — using .env.example + user overrides"
  fi

  podman-compose -f "$compose_file" --env-file "$env_file" -p "$project_name" "$@"
  local ret=$?
  rm -f "$env_file"
  return $ret
}
```

### 4. Create `lib/services/service.sh`

Defines `profile_install()`, `profile_remove()`, and registers service-specific commands.

```bash
#!/usr/bin/env bash
# Service backend — install/remove and lifecycle commands

# Install a service: create instance directory, link registry
# Arguments: asset_dir asset_name
profile_install() {
  local asset_dir="$1" asset_name="$2"

  _require_podman

  # Determine the network for this service
  local network
  network=$(_resolve_network "$asset_dir" "${_PSM_INSTALL_NETWORK:-}")

  # Ensure the network exists
  _ensure_network "$network"

  local instance_dir="${PSM_SERVICES_HOME}/${network}/${asset_name}"

  # Skip if already installed at this network location
  if [[ -d "$instance_dir/data" ]]; then
    debug "$asset_name already installed on network $network"
    PROFILE_STOWED_FILES=""
    return 0
  fi

  # System scope requires root
  if [[ "$PSM_SCOPE" == "system" && $EUID -ne 0 ]]; then
    echo "psm: System services require root. Use: sudo psm install ${asset_name} --system" >&2
    exit 1
  fi

  # Create instance directory structure
  mkdir -p "${instance_dir}/config"
  mkdir -p "${instance_dir}/data"

  # Link the service definition from the source repo
  ln -sfn "$asset_dir" "${instance_dir}/registry"

  echo "  network:  $network"
  echo "  data:     ${instance_dir}/data"
  echo "  config:   ${instance_dir}/config"

  # No stowed files for services — tracking is directory-based
  PROFILE_STOWED_FILES=""
}

# Remove a service: stop containers, remove instance directory
# Arguments: asset_dir asset_name
profile_remove() {
  local asset_dir="$1" asset_name="$2"

  local network
  network=$(_resolve_network "$asset_dir" "${_PSM_INSTALL_NETWORK:-}")

  local instance_dir="${PSM_SERVICES_HOME}/${network}/${asset_name}"

  if [[ ! -d "$instance_dir" ]]; then
    debug "$asset_name not installed on network $network"
    return 0
  fi

  # Stop containers if running
  if [[ -L "$instance_dir/registry" || -d "$instance_dir/registry" ]]; then
    local compose_file
    compose_file=$(_find_compose_file "$instance_dir/registry" 2>/dev/null) || true
    if [[ -n "$compose_file" ]]; then
      debug "Stopping containers for $asset_name"
      _compose_run "$asset_name" "$network" down 2>/dev/null || true
    fi
  fi

  # Remove the instance directory
  # NOTE: data/ is preserved by default. Use --purge to remove data.
  rm -f "${instance_dir}/registry"
  rmdir "${instance_dir}/config" 2>/dev/null || true
  # Do NOT remove data/ — it contains persistent state

  echo "  Removed instance (data preserved at ${instance_dir}/data)"
}
```

### 5. Update the main ppm script's flag parser

The main script's global flag parser currently handles `-v`, `--debug`, etc. Add a hook for backend-specific flags:

In the flag parsing loop, after checking known flags:

```bash
# Try backend-specific flag parser if available
if type parse_backend_flag &>/dev/null; then
  if parse_backend_flag "$1"; then
    shift
    continue
  fi
fi
```

This must come AFTER backend libs are sourced but BEFORE command dispatch. Since flags are parsed in the main script's initial loop (before sourcing), we need to restructure slightly:

**Option A**: Move flag parsing after lib sourcing (preferred). Parse flags in a function called after all libs are sourced.

**Option B**: Pre-scan for `--user`/`--system`/`-s` in the env var bootstrap. Since these are PSM-specific flags that only matter when `PPM_ASSET_DIR=services`, they can be parsed conditionally.

Go with Option A — refactor the main script so:
1. Bootstrap env vars
2. Resolve path, source libs
3. Parse flags (with backend flag support)
4. Dispatch command

### 6. Wire up network context during dependency resolution

When installing a meta-service with `network: gatekeeper`, all its dependencies should be installed on the same network. The installer needs to pass network context through the dep resolution chain.

In `lib/installer.sh`, before resolving deps for a service:

```bash
# Read network from the top-level service being installed
local declared_network
declared_network=$(_service_network "$asset_dir" 2>/dev/null)
if [[ -n "$declared_network" ]]; then
  export _PSM_INSTALL_NETWORK="$declared_network"
fi
```

The `_PSM_INSTALL_NETWORK` env var is read by `profile_install()` to determine which network directory to use. It's exported so subprocess installs (dep resolution calls `$0 installer ...`) inherit it.

After the top-level install completes, unset it:

```bash
unset _PSM_INSTALL_NETWORK
```

This is only relevant when the service backend is loaded. When running as ppm, `_service_network` is not defined and the code path is never hit. Guard with:

```bash
if type _service_network &>/dev/null; then
  # ... network context logic ...
fi
```

## Test Spec

Requires a service repo with at least one service definition. Create a minimal test setup:

```bash
# Create a test service repo
mkdir -p /tmp/test-psm-repo/services/hello
cat > /tmp/test-psm-repo/services/hello/package.yml <<'EOF'
version: 0.1.0
EOF
cat > /tmp/test-psm-repo/services/hello/compose.yml <<'EOF'
services:
  hello:
    image: docker.io/library/hello-world:latest
    container_name: ${PSM_NETWORK}-hello
networks:
  default:
    external: true
    name: ${PSM_NETWORK}
EOF
cat > /tmp/test-psm-repo/services/hello/.env.example <<'EOF'
EOF

# Add to psm sources
psm src add /tmp/test-psm-repo test-psm
```

### Install test

```bash
psm install hello
# Should create ~/.local/share/psm/services/psm/hello/{config,data,registry}
ls -la ~/.local/share/psm/services/psm/hello/
ls -la ~/.local/share/psm/services/psm/hello/registry  # symlink to /tmp/test-psm-repo/services/hello
```

### Network isolation test

```bash
# Create a meta-service with network isolation
mkdir -p /tmp/test-psm-repo/services/mystack
cat > /tmp/test-psm-repo/services/mystack/package.yml <<'EOF'
version: 0.1.0
depends:
  - hello
network: mystack
EOF

psm install mystack
# Should create:
#   ~/.local/share/psm/services/mystack/hello/{config,data,registry}
#   ~/.local/share/psm/services/mystack/mystack/{config,data,registry}
ls -la ~/.local/share/psm/services/mystack/
```

### List/show test

```bash
psm list                     # shows hello, mystack
psm list --installed         # shows installed instances
psm show hello               # shows metadata, install location
```

## Verification

- [ ] `lib/services/scope.sh` exists with `_resolve_scope()` and `parse_backend_flag()`
- [ ] `lib/services/network.sh` exists with `_ensure_network()`, `_service_network()`, `_resolve_network()`
- [ ] `lib/services/compose.sh` exists with `_require_podman()`, `_build_env_file()`, `_compose_run()`
- [ ] `lib/services/service.sh` exists with `profile_install()` and `profile_remove()`
- [ ] `psm install hello` creates correct directory structure under `services/psm/hello/`
- [ ] Registry symlink points to the correct source repo location
- [ ] `--user`/`--system` flags are parsed when service backend is loaded
- [ ] Network isolation: meta-service with `network:` key scopes deps under that network
- [ ] `psm list` shows services from source repos
- [ ] `psm show hello` shows metadata and install status
- [ ] `ppm list` still works (service backend not loaded for ppm)
- [ ] `ppm install zsh` still works
