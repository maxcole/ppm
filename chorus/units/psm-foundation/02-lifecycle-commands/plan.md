---
---

# Plan 02 — Service Lifecycle Commands

## Context — read these files first

- `lib/services/service.sh` — `profile_install()`, `profile_remove()` from plan 01
- `lib/services/compose.sh` — `_compose_run()` from plan 01
- `lib/services/network.sh` — `_resolve_network()` from plan 01
- `lib/graph.sh` — `resolve_deps()`, `RESOLVE_ORDER`, `RESOLVE_DIRS`
- `ppm` — main script command dispatch (the `case` statement at the bottom)

## Overview

Add service lifecycle commands: `up`, `down`, `restart`, `logs`, `status`. These are registered by the service backend and only available when running as `psm`. They use dependency-aware ordering — `psm up gatekeeper` starts services in topo order, `psm down gatekeeper` stops in reverse order.

Also add the `--up` flag to `psm install` which starts services after installation.

## Implementation

### 1. Command registration mechanism

The main ppm script dispatches commands via a `case` statement. Backend libraries need to add commands without modifying the main script. Two approaches:

**Approach (chosen):** The main script's dispatch has a fallback that calls a `backend_command()` function if defined:

```bash
# In main script dispatch:
case "$command" in
  install|remove|list|show|deps|update|src|path|cd|completion|package|config|help)
    "$command" "$@"
    ;;
  *)
    if type backend_command &>/dev/null; then
      backend_command "$command" "$@"
    else
      echo "Error: Unknown command '$command'"
      list_commands
      exit 1
    fi
    ;;
esac
```

The service backend defines `backend_command()` in `lib/services/service.sh` to handle `up`, `down`, `restart`, `logs`, `status`.

### 2. Add `backend_command()` to `lib/services/service.sh`

```bash
# Service-specific command dispatch
# Called by the main script for commands not in the core set
backend_command() {
  local cmd="$1"
  shift

  case "$cmd" in
    up)      cmd_up "$@" ;;
    down)    cmd_down "$@" ;;
    restart) cmd_restart "$@" ;;
    logs)    cmd_logs "$@" ;;
    status)  cmd_status "$@" ;;
    *)       return 1 ;;
  esac
}
```

### 3. Implement `cmd_up`

Dependency-aware startup. Resolves the full dep tree and starts each service in order.

```bash
cmd_up() {
  local service="${1:-}"
  [[ -z "$service" ]] && { echo "Usage: psm up <service>"; exit 1; }
  shift

  _require_podman
  collect_repos
  resolve_deps "$service"

  # Determine network from the top-level service
  local top_dir
  top_dir=$(find_package_dir "$service") || { echo "psm: Service '$service' not found" >&2; exit 1; }
  top_dir="${top_dir#*	}"; top_dir="${top_dir#*	}"  # extract pkg_dir from tab-separated output
  local network
  network=$(_resolve_network "$top_dir")

  _ensure_network "$network"

  for i in "${!RESOLVE_ORDER[@]}"; do
    local qualified="${RESOLVE_ORDER[$i]}"
    local svc_name="${qualified##*/}"
    local svc_asset_dir="${RESOLVE_DIRS[$i]}"

    local instance_dir="${PSM_SERVICES_HOME}/${network}/${svc_name}"

    # Auto-install if not installed
    if [[ ! -d "$instance_dir/data" ]]; then
      debug "Auto-installing $svc_name"
      _PSM_INSTALL_NETWORK="$network" profile_install "$svc_asset_dir" "$svc_name"
    fi

    # Skip services with no compose file (meta-services / bundles)
    local compose_file
    compose_file=$(_find_compose_file "$instance_dir/registry" 2>/dev/null) || {
      debug "No compose file for $svc_name — skipping start"
      continue
    }

    # Check if already running
    local project_name="${network}-${svc_name}"
    if podman-compose -p "$project_name" -f "$compose_file" ps 2>/dev/null | grep -q "Up\|running"; then
      debug "$svc_name already running on $network"
      continue
    fi

    echo "Starting $svc_name"
    _compose_run "$svc_name" "$network" up -d "$@"
  done
}
```

### 4. Implement `cmd_down`

Reverse dependency order shutdown.

```bash
cmd_down() {
  local service="${1:-}"
  [[ -z "$service" ]] && { echo "Usage: psm down <service>"; exit 1; }

  _require_podman
  collect_repos
  resolve_deps "$service"

  local top_dir
  top_dir=$(find_package_dir "$service") || { echo "psm: Service '$service' not found" >&2; exit 1; }
  top_dir="${top_dir#*	}"; top_dir="${top_dir#*	}"
  local network
  network=$(_resolve_network "$top_dir")

  # Reverse order — stop dependents first
  local count=${#RESOLVE_ORDER[@]}
  for (( i=count-1; i>=0; i-- )); do
    local qualified="${RESOLVE_ORDER[$i]}"
    local svc_name="${qualified##*/}"

    local instance_dir="${PSM_SERVICES_HOME}/${network}/${svc_name}"
    [[ ! -d "$instance_dir/registry" ]] && continue

    local compose_file
    compose_file=$(_find_compose_file "$instance_dir/registry" 2>/dev/null) || continue

    echo "Stopping $svc_name"
    _compose_run "$svc_name" "$network" down 2>/dev/null || true
  done
}
```

### 5. Implement `cmd_restart`

```bash
cmd_restart() {
  local service="${1:-}"
  [[ -z "$service" ]] && { echo "Usage: psm restart <service>"; exit 1; }

  cmd_down "$service"
  cmd_up "$service"
}
```

### 6. Implement `cmd_logs`

```bash
cmd_logs() {
  local service="${1:-}"
  [[ -z "$service" ]] && { echo "Usage: psm logs <service> [-f]"; exit 1; }
  shift

  # Determine network — check installed locations
  local network
  network=$(_find_installed_network "$service")

  _compose_run "$service" "$network" logs "$@"
}
```

### 7. Implement `cmd_status`

```bash
cmd_status() {
  local service="${1:-}"

  _require_podman

  if [[ -z "$service" ]]; then
    # Show all PSM services grouped by network
    echo "PSM services:"
    if [[ -d "$PSM_SERVICES_HOME" ]]; then
      for network_dir in "$PSM_SERVICES_HOME"/*/; do
        [[ -d "$network_dir" ]] || continue
        local network=$(basename "$network_dir")
        echo ""
        echo "  $network:"
        for svc_dir in "$network_dir"/*/; do
          [[ -d "$svc_dir/registry" ]] || continue
          local svc_name=$(basename "$svc_dir")
          local project_name="${network}-${svc_name}"
          local status="stopped"
          if podman ps --filter "label=com.docker.compose.project=${project_name}" --format "{{.Status}}" 2>/dev/null | grep -qi "up\|running"; then
            status="running"
          fi
          printf "    %-20s %s\n" "$svc_name" "$status"
        done
      done
    fi
  else
    # Show status for a specific service
    local network
    network=$(_find_installed_network "$service")
    _compose_run "$service" "$network" ps
  fi
}
```

### 8. Helper: find installed network for a service

When a user runs `psm logs postgres`, we need to find which network(s) postgres is installed on. If it's only on one network, use it. If multiple, require disambiguation.

```bash
# Find which network a service is installed on
# If on exactly one network, prints it. If multiple, errors with disambiguation help.
# Usage: _find_installed_network <service_name>
_find_installed_network() {
  local service="$1"
  local found=()

  if [[ -d "$PSM_SERVICES_HOME" ]]; then
    for network_dir in "$PSM_SERVICES_HOME"/*/; do
      [[ -d "$network_dir" ]] || continue
      local network=$(basename "$network_dir")
      if [[ -d "$network_dir/$service" ]]; then
        found+=("$network")
      fi
    done
  fi

  if [[ ${#found[@]} -eq 0 ]]; then
    echo "psm: Service '$service' is not installed" >&2
    exit 1
  elif [[ ${#found[@]} -eq 1 ]]; then
    echo "${found[0]}"
  else
    echo "psm: Service '$service' exists on multiple networks: ${found[*]}" >&2
    echo "psm: Specify with: psm <command> <network>/$service" >&2
    exit 1
  fi
}
```

Also support `network/service` syntax in command parsing. If the argument contains `/`, split it:

```bash
# At the top of cmd_up, cmd_down, cmd_logs, etc:
local network_override=""
if [[ "$service" == */* ]]; then
  network_override="${service%%/*}"
  service="${service##*/}"
fi
```

Use `network_override` instead of resolving from the dep tree or searching installed dirs when it's provided.

### 9. Add `--up` flag to install

In the main script's `install()` entry point (or in `lib/installer.sh`), check for an `--up` flag when the service backend is loaded:

```bash
# In install() entry point, after expand_packages:
local start_after_install=false
# Check if --up was in the args (parsed alongside other flags)
# ... flag parsing ...

if $start_after_install && type cmd_up &>/dev/null; then
  for pkg in "${EXPANDED_PACKAGES[@]}"; do
    cmd_up "$(basename "$pkg")"
  done
fi
```

The `--up` flag is only meaningful for the service backend. For the package backend, it's silently ignored.

### 10. Update help text

The `help` command (or `list_commands`) should include lifecycle commands when the service backend is loaded:

```bash
# In list_commands or the help function:
if type backend_command &>/dev/null; then
  echo ""
  echo "Service lifecycle:"
  echo "  up <service>          Start a service (auto-installs if needed)"
  echo "  down <service>        Stop a service"
  echo "  restart <service>     Restart a service"
  echo "  logs <service> [-f]   View service logs"
  echo "  status [<service>]    Show running service status"
fi
```

## Test Spec

Uses the test service repo from plan 01.

### Lifecycle

```bash
psm install hello
psm up hello                # should start container
psm status                  # should show hello as running under psm network
psm logs hello              # should show container output
psm restart hello           # should stop and start
psm down hello              # should stop container
psm status                  # should show hello as stopped
```

### Auto-install on up

```bash
psm remove test-psm/hello
psm up hello                # should auto-install then start
```

### Install --up

```bash
psm remove test-psm/hello
psm install hello --up      # should install and start
psm status                  # should show running
```

### Dependency-aware up/down

```bash
# Using mystack meta-service from plan 01 test
psm up mystack              # should start hello first (dep), then mystack
psm status                  # should show both under mystack network
psm down mystack            # should stop mystack first, then hello
```

### Network/service disambiguation

```bash
# With hello installed on both psm and mystack networks:
psm logs hello              # should error: "exists on multiple networks"
psm logs psm/hello          # should work
psm logs mystack/hello      # should work
```

## Verification

- [ ] `backend_command()` defined in `lib/services/service.sh`
- [ ] Main script dispatch falls through to `backend_command()` for unknown commands
- [ ] `psm up hello` starts the service container
- [ ] `psm down hello` stops the service container
- [ ] `psm restart hello` cycles the service
- [ ] `psm logs hello` shows container logs
- [ ] `psm status` shows all services grouped by network
- [ ] `psm status hello` shows specific service status
- [ ] `psm up mystack` starts dependencies in topo order before the meta-service
- [ ] `psm down mystack` stops in reverse order
- [ ] `psm up hello` auto-installs if not installed
- [ ] `psm install hello --up` installs and starts
- [ ] `network/service` syntax works for disambiguation
- [ ] `ppm up` fails with "unknown command" (lifecycle commands only in service backend)
- [ ] Help text includes lifecycle commands when service backend is loaded
