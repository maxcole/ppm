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
  if [[ -f "$example_env" ]]; then
    cat "$example_env" >> "$env_file"
  fi

  # User overrides
  local user_env="${instance_dir}/config/.env"
  if [[ -f "$user_env" ]]; then
    cat "$user_env" >> "$env_file"
  fi

  echo "$env_file"
}

# Find the compose file in a registry directory
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

  local env_file
  env_file=$(_build_env_file "$service" "$instance_dir" "$registry_dir" "$network")

  local project_name="${network}-${service}"

  # Varlock path: validate schema + resolve credentials, then run compose
  if [[ -z "${PSM_SKIP_VALIDATION:-}" ]] \
     && command -v varlock >/dev/null 2>&1 \
     && [[ -f "${registry_dir}/.schema.env" ]]; then
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
    debug "Validation skipped (--skip-validation)"
  else
    debug "No varlock — using .env.example + user overrides"
  fi

  podman-compose -f "$compose_file" --env-file "$env_file" -p "$project_name" "$@"
  local ret=$?
  rm -f "$env_file"
  return $ret
}
