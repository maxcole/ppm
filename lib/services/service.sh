#!/usr/bin/env bash
# Service backend — install/remove profile functions

# Install a service: create instance directory, link registry
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

  # Remove the instance directory (data preserved)
  rm -f "${instance_dir}/registry"
  rmdir "${instance_dir}/config" 2>/dev/null || true

  echo "  Removed instance (data preserved at ${instance_dir}/data)"
}

# --- Lifecycle commands ---

# Service-specific command dispatch
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

# Parse network/service syntax
# Sets _lc_network and _lc_service in caller's scope
_parse_service_arg() {
  local arg="$1"
  _lc_network=""
  _lc_service=""

  if [[ "$arg" == */* ]]; then
    _lc_network="${arg%%/*}"
    _lc_service="${arg##*/}"
  else
    _lc_service="$arg"
  fi
}

# Find which network a service is installed on
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
    return 1
  elif [[ ${#found[@]} -eq 1 ]]; then
    echo "${found[0]}"
  else
    echo "psm: Service '$service' exists on multiple networks: ${found[*]}" >&2
    echo "psm: Specify with: psm <command> <network>/$service" >&2
    return 1
  fi
}

# Resolve network for a lifecycle command
# Uses explicit network/service syntax, or finds the installed network
_resolve_lifecycle_network() {
  local service="$1" explicit_network="$2"

  if [[ -n "$explicit_network" ]]; then
    echo "$explicit_network"
    return
  fi

  # Try to resolve from dep tree (service definition)
  collect_repos
  local found
  found=$(find_package_dir "$service" 2>/dev/null) || true
  if [[ -n "$found" ]]; then
    local pkg_dir="${found#*	}"
    pkg_dir="${pkg_dir#*	}"
    local net
    net=$(_resolve_network "$pkg_dir")
    echo "$net"
    return
  fi

  # Fall back to scanning installed dirs
  _find_installed_network "$service"
}

cmd_up() {
  local arg="${1:-}"
  [[ -z "$arg" ]] && { echo "Usage: psm up <service>"; exit 1; }
  shift

  _parse_service_arg "$arg"
  local service="$_lc_service"
  local network_override="$_lc_network"

  _require_podman
  collect_repos
  resolve_deps "$service"

  # Determine network from the top-level service
  local top_dir
  top_dir=$(find_package_dir "$service") || { echo "psm: Service '$service' not found" >&2; exit 1; }
  top_dir="${top_dir#*	}"; top_dir="${top_dir#*	}"
  local network
  if [[ -n "$network_override" ]]; then
    network="$network_override"
  else
    network=$(_resolve_network "$top_dir")
  fi

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
      # Track the auto-install
      local repo_name="${qualified%%/*}"
      meta_mark_installed "$repo_name" "$svc_name" "$svc_asset_dir" ""
    fi

    # Skip services with no compose file (meta-services / bundles)
    local compose_file
    compose_file=$(_find_compose_file "$instance_dir/registry" 2>/dev/null) || {
      debug "No compose file for $svc_name — skipping start"
      continue
    }

    echo "Starting $svc_name"
    _compose_run "$svc_name" "$network" up -d "$@"
  done
}

cmd_down() {
  local arg="${1:-}"
  [[ -z "$arg" ]] && { echo "Usage: psm down <service>"; exit 1; }

  _parse_service_arg "$arg"
  local service="$_lc_service"
  local network_override="$_lc_network"

  _require_podman
  collect_repos
  resolve_deps "$service"

  local top_dir
  top_dir=$(find_package_dir "$service") || { echo "psm: Service '$service' not found" >&2; exit 1; }
  top_dir="${top_dir#*	}"; top_dir="${top_dir#*	}"
  local network
  if [[ -n "$network_override" ]]; then
    network="$network_override"
  else
    network=$(_resolve_network "$top_dir")
  fi

  # Reverse order — stop dependents first
  local count=${#RESOLVE_ORDER[@]}
  local i=$((count - 1))
  while [[ $i -ge 0 ]]; do
    local qualified="${RESOLVE_ORDER[$i]}"
    local svc_name="${qualified##*/}"

    local instance_dir="${PSM_SERVICES_HOME}/${network}/${svc_name}"
    if [[ -d "$instance_dir/registry" ]] || [[ -L "$instance_dir/registry" ]]; then
      local compose_file
      compose_file=$(_find_compose_file "$instance_dir/registry" 2>/dev/null) || { i=$((i - 1)); continue; }

      echo "Stopping $svc_name"
      _compose_run "$svc_name" "$network" down 2>/dev/null || true
    fi
    i=$((i - 1))
  done
}

cmd_restart() {
  local arg="${1:-}"
  [[ -z "$arg" ]] && { echo "Usage: psm restart <service>"; exit 1; }

  cmd_down "$arg"
  cmd_up "$arg"
}

cmd_logs() {
  local arg="${1:-}"
  [[ -z "$arg" ]] && { echo "Usage: psm logs <service> [-f]"; exit 1; }
  shift

  _parse_service_arg "$arg"
  local service="$_lc_service"
  local network

  if [[ -n "$_lc_network" ]]; then
    network="$_lc_network"
  else
    network=$(_find_installed_network "$service") || exit 1
  fi

  _compose_run "$service" "$network" logs "$@"
}

cmd_status() {
  local arg="${1:-}"

  _require_podman

  if [[ -z "$arg" ]]; then
    # Show all PSM services grouped by network
    echo "PSM services:"
    if [[ -d "$PSM_SERVICES_HOME" ]]; then
      for network_dir in "$PSM_SERVICES_HOME"/*/; do
        [[ -d "$network_dir" ]] || continue
        local network=$(basename "$network_dir")
        echo ""
        echo "  $network:"
        for svc_dir in "$network_dir"/*/; do
          [[ -d "$svc_dir" ]] || continue
          [[ -L "$svc_dir/registry" || -d "$svc_dir/registry" ]] || continue
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
    _parse_service_arg "$arg"
    local service="$_lc_service"
    local network

    if [[ -n "$_lc_network" ]]; then
      network="$_lc_network"
    else
      network=$(_find_installed_network "$service") || exit 1
    fi

    _compose_run "$service" "$network" ps
  fi
}
