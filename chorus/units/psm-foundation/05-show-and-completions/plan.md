---
---

# Plan 05 — Enhanced Show and Zsh Completions

## Context — read these files first

- `ppm` — `show()` function (existing package show implementation)
- `ppm` — `completion()` function (existing zsh completion generation)
- `lib/services/service.sh` — `backend_command()`, lifecycle commands (plan 02)
- `lib/services/network.sh` — `_find_installed_network()` (plan 02)
- `lib/graph.sh` — `resolve_deps()`, `RESOLVE_ORDER` for dep tree display

## Overview

Enhance the `show` command for the service backend to display service-specific information: running status, dependency tree, network assignment, ports, and compose details. Add zsh completions for all PSM commands and service names.

## Implementation

### 1. Service-aware `show` command

The existing `show()` function in the main script works for both packages and services since it reads `package.yml` and shows the directory tree. Enhance it for services by adding a `backend_show()` hook that the service backend defines:

In the main script's `show()` function, after the generic display:

```bash
# Call backend-specific show if available
if type backend_show &>/dev/null; then
  backend_show "$pkg_dir" "$package_name" "$repo_name"
fi
```

In `lib/services/service.sh`:

```bash
# Enhanced show output for services
# Called after the generic show output
backend_show() {
  local asset_dir="$1" asset_name="$2" repo_name="$3"

  # Service metadata from psm.yml
  local psm_meta="$asset_dir/psm.yml"
  if [[ -f "$psm_meta" ]] && command -v yq >/dev/null 2>&1; then
    local desc
    desc=$(yq -r '.description // ""' "$psm_meta" 2>/dev/null)
    [[ -n "$desc" && "$desc" != "null" ]] && echo "About:       $desc"

    local ports
    ports=$(yq -r '.ports[]? // ""' "$psm_meta" 2>/dev/null)
    if [[ -n "$ports" ]]; then
      echo "Ports:"
      echo "$ports" | while IFS= read -r p; do
        [[ -n "$p" ]] && echo "  $p"
      done
    fi
  fi

  # Network
  local network
  network=$(_service_network "$asset_dir")
  if [[ -n "$network" ]]; then
    echo "Network:     $network (isolated)"
  else
    echo "Network:     psm (default, shared)"
  fi

  # PCM credentials
  if [[ -f "$asset_dir/pcm.yml" ]]; then
    echo "Credentials: pcm.yml present"
  fi

  # Resolved dependency tree
  echo ""
  collect_repos
  resolve_deps "$asset_name"
  if [[ ${#RESOLVE_ORDER[@]} -gt 1 ]]; then
    echo "Resolved install order:"
    for pkg in "${RESOLVE_ORDER[@]}"; do
      local marker=""
      [[ "$(basename "$pkg")" == "$asset_name" ]] && marker=" (this)"
      echo "  $(basename "$pkg")${marker}"
    done
  fi

  # Installed instance status
  echo ""
  local found_instances=false
  if [[ -d "$PSM_SERVICES_HOME" ]]; then
    for network_dir in "$PSM_SERVICES_HOME"/*/; do
      [[ -d "$network_dir" ]] || continue
      local net=$(basename "$network_dir")
      local instance_dir="$network_dir/$asset_name"
      [[ -d "$instance_dir" ]] || continue

      found_instances=true
      local status="stopped"
      local project_name="${net}-${asset_name}"
      if podman ps --filter "label=com.docker.compose.project=${project_name}" --format "{{.Status}}" 2>/dev/null | grep -qi "up\|running"; then
        status="running"
      fi

      echo "Instance:    $net/$asset_name ($status)"
      echo "  data:      $instance_dir/data"
      echo "  config:    $instance_dir/config"
    done
  fi

  if ! $found_instances; then
    echo "Installed:   no"
    echo "  Install with: psm install $asset_name"
  fi
}
```

### 2. Zsh completions for PSM

The existing `completion()` function generates completions for `ppm`. Add a service-backend version that generates completions for `psm`. The backend can override or extend `completion()`.

In `lib/services/service.sh`, define `backend_completion()`:

```bash
backend_completion() {
  local shell="${1:-zsh}"
  case "$shell" in
    zsh)
      cat <<'COMP'
#compdef psm

_psm() {
    local -a subcommands
    local state

    subcommands=(
        'install:Install a service'
        'remove:Remove a service'
        'update:Update service repositories'
        'list:List available services'
        'ls:List available services (alias)'
        'show:Show service information'
        'deps:Show dependency tree'
        'src:Manage service sources'
        'up:Start a service'
        'down:Stop a service'
        'restart:Restart a service'
        'logs:View service logs'
        'status:Show service status'
        'path:Output path to a service directory'
        'cd:Change to a service directory'
        'config:Show PSM configuration'
        'help:Show help'
    )

    _arguments -C \
        '(-v)-v[Verbose output]' \
        '(-s --skip-validation)-s[Skip validation]' \
        '--skip-validation[Skip validation]' \
        '--user[Force user scope]' \
        '--system[Force system scope]' \
        '1: :->command' \
        '*: :->args'

    case $state in
        command)
            _describe 'command' subcommands
            ;;
        args)
            case ${words[2]} in
                src)
                    if [[ ${#words[@]} -eq 3 ]]; then
                        local -a src_cmds
                        src_cmds=('add:Add a service source' 'remove:Remove a service source' 'list:List configured sources')
                        _describe 'subcommand' src_cmds
                    fi
                    ;;
                install|remove|show|deps|up|down|restart|logs|status|path|cd)
                    _psm_services_available
                    ;;
            esac
            ;;
    esac
}

_psm_services_available() {
    local -a services
    local psm_data_home="${XDG_DATA_HOME:-$HOME/.local/share}/psm"

    # Available from repos
    for repo_dir in "$psm_data_home"/*/services; do
        [[ -d "$repo_dir" ]] || continue
        local repo_name="${repo_dir%/services}"
        repo_name="${repo_name##*/}"
        for svc_dir in "$repo_dir"/*/; do
            [[ -d "$svc_dir" ]] || continue
            local svc_name="${svc_dir%/}"
            svc_name="${svc_name##*/}"
            services+=("${repo_name}/${svc_name}")
        done
    done

    # Installed instances (network/service)
    local services_home="$psm_data_home/services"
    if [[ -d "$services_home" ]]; then
        for network_dir in "$services_home"/*/; do
            [[ -d "$network_dir" ]] || continue
            local network="${network_dir%/}"
            network="${network##*/}"
            for svc_dir in "$network_dir"/*/; do
                [[ -d "$svc_dir" ]] || continue
                local svc_name="${svc_dir%/}"
                svc_name="${svc_name##*/}"
                services+=("${network}/${svc_name}")
            done
        done
    fi

    _describe 'service' services
}

compdef _psm psm
COMP
      ;;
    *)
      echo "# Completion for $shell not yet implemented" ;;
  esac
}
```

Wire this into the main completion dispatch. When the service backend is loaded and `completion` is called, use `backend_completion` instead of the default package completion. In the main script:

```bash
completion() {
  if type backend_completion &>/dev/null; then
    backend_completion "$@"
  else
    # ... existing package completion ...
  fi
}
```

Or better — the existing completion function stays for `ppm`, and the service backend overrides it. Since `lib/services/*.sh` is sourced after `lib/*.sh`, a `completion()` function in the service backend would shadow the one in the main script. However, `completion()` is defined in the main script body, not in a lib file. So the service backend should define `backend_completion()` and the main dispatch calls it when available.

### 3. Update the psm zsh package to source completions

In `packages/psm/home/.config/zsh/psm/psm.zsh`, add:

```zsh
# Load PSM completions
if command -v ppm >/dev/null 2>&1; then
  eval "$(PSM_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}/psm" \
    PPM_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}/psm" \
    PPM_ASSET_DIR=services \
    PPM_ASSET_HOOK=service.sh \
    PPM_ASSET_LABEL=service \
    command ppm completion zsh 2>/dev/null)"
fi
```

## Test Spec

### Enhanced show

```bash
psm show postgres
# Should display:
#   Package: psm-ppm/postgres (standard engine output)
#   About: PostgreSQL 16 relational database
#   Ports: 5432
#   Network: psm (default, shared)
#   Installed: no / yes with instance details and running status

psm show gatekeeper
# Should display:
#   Network: gatekeeper (isolated)
#   Resolved install order: postgres → redis → gatekeeper
```

### Completions

```bash
# After shell reload:
psm <TAB>
# Should show: install remove update list show deps src up down restart logs status ...

psm install <TAB>
# Should show available services from repos

psm up <TAB>
# Should show available services (both from repos and installed instances)

psm logs <TAB>
# Should show installed instances (network/service format)
```

## Verification

- [ ] `psm show postgres` displays service metadata (description, ports, network)
- [ ] `psm show gatekeeper` displays resolved dependency tree
- [ ] `psm show postgres` shows installed instance status when installed
- [ ] `psm show postgres` shows running/stopped status
- [ ] `psm completion zsh` outputs valid zsh completion code for PSM commands
- [ ] Tab completion works for all PSM commands
- [ ] Tab completion shows service names from repos and installed instances
- [ ] `ppm show zsh` still works (package backend unaffected)
- [ ] `ppm completion zsh` still generates ppm completions (not psm completions)
