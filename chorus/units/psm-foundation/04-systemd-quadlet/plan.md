---
---

# Plan 04 — Systemd Quadlet Generation

## Context — read these files first

- `lib/services/scope.sh` — `_resolve_scope()`, `PSM_SCOPE`, `PSM_HOME` (plan 01)
- `lib/services/service.sh` — `profile_install()` (plan 01)
- `lib/services/compose.sh` — `_compose_run()`, `_build_env_file()` (plan 01)
- `lib/graph.sh` — `resolve_deps()`, `RESOLVE_ORDER` for dependency chain
- Podman Quadlet documentation: https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html

## Overview

When `--system` scope is used, `psm install` generates Podman Quadlet unit files that systemd manages. This means `psm up`/`psm down` in system scope delegate to `systemctl start`/`systemctl stop` rather than calling `podman-compose` directly. Dependencies map to systemd `After=`/`Requires=` directives, giving the OS responsibility for startup ordering and restart behavior.

User scope (`--user`, the default) continues to use `podman-compose` directly — no systemd integration.

## Implementation

### 1. Quadlet file generation

Add `_generate_quadlet()` to `lib/services/scope.sh` (or a new `lib/services/quadlet.sh`):

```bash
# Generate a Podman Quadlet .container file for systemd management
# Usage: _generate_quadlet <service_name> <network> <instance_dir> <asset_dir>
_generate_quadlet() {
  local service="$1" network="$2" instance_dir="$3" asset_dir="$4"

  local quadlet_dir="/etc/containers/systemd"
  mkdir -p "$quadlet_dir"

  local unit_name="psm-${network}-${service}"
  local compose_file
  compose_file=$(_find_compose_file "$asset_dir" 2>/dev/null) || return 0  # skip meta-services

  local env_file="${instance_dir}/config/quadlet.env"

  # Write a persistent env file (not a tempfile — systemd needs it at boot)
  _build_env_file "$service" "$instance_dir" "$asset_dir" "$network" > "$env_file"

  # Build dependency directives from package.yml
  local after_units=""
  local requires_units=""
  local deps
  deps=$(resolve_package_deps "$asset_dir")
  if [[ -n "$deps" ]]; then
    for dep in $deps; do
      local dep_name="${dep##*/}"
      after_units="${after_units}After=psm-${network}-${dep_name}.service\n"
      requires_units="${requires_units}Requires=psm-${network}-${dep_name}.service\n"
    done
  fi

  cat > "${quadlet_dir}/${unit_name}.container" <<EOF
[Unit]
Description=PSM service: ${service} (${network})
$(echo -e "$after_units")$(echo -e "$requires_units")
[Container]
ContainerName=${network}-${service}
PodmanArgs=--network ${network}
EnvironmentFile=${env_file}

# Pull compose image — Quadlet needs the image directly
# This is extracted from compose.yml; for multi-container services
# a .kube or .pod Quadlet may be more appropriate
# TODO: parse compose.yml to extract image and volume mounts

[Service]
Restart=always
TimeoutStartSec=300

[Install]
WantedBy=multi-user.target
EOF

  debug "Generated Quadlet: ${quadlet_dir}/${unit_name}.container"
}
```

**Important caveat:** Quadlet `.container` files map 1:1 with containers. Multi-container services (like authentik with server + worker) need either multiple `.container` files or a `.kube` Quadlet. For the foundation tier, support single-container services. Multi-container Quadlet support is a production-tier concern.

For this plan, the approach is:
- Parse `compose.yml` to extract the first (or only) service's image and volume mounts
- Generate a `.container` Quadlet
- If the compose file has multiple services, warn and skip Quadlet generation with a message suggesting `podman-compose` management

### 2. Modify `profile_install()` for system scope

In `lib/services/service.sh`, add Quadlet generation when installing in system scope:

```bash
profile_install() {
  local asset_dir="$1" asset_name="$2"
  # ... existing install logic ...

  # Generate Quadlet for system scope
  if [[ "$PSM_SCOPE" == "system" ]]; then
    _generate_quadlet "$asset_name" "$network" "$instance_dir" "$asset_dir"
    systemctl daemon-reload
    systemctl enable "psm-${network}-${asset_name}" 2>/dev/null || true
    echo "  systemd:  psm-${network}-${asset_name}.service (enabled)"
  fi
}
```

### 3. Modify lifecycle commands for system scope

In `cmd_up` and `cmd_down`, check scope and delegate to systemctl:

```bash
cmd_up() {
  # ... existing logic ...

  if [[ "$PSM_SCOPE" == "system" ]]; then
    for svc in resolved_order; do
      local unit_name="psm-${network}-${svc_name}"
      echo "Starting $svc_name (systemd)"
      systemctl start "$unit_name"
    done
    return
  fi

  # ... existing podman-compose logic for user scope ...
}

cmd_down() {
  # ... existing logic ...

  if [[ "$PSM_SCOPE" == "system" ]]; then
    # Reverse order
    for svc in reversed_order; do
      local unit_name="psm-${network}-${svc_name}"
      echo "Stopping $svc_name (systemd)"
      systemctl stop "$unit_name"
    done
    return
  fi

  # ... existing podman-compose logic ...
}
```

### 4. Status command shows systemd status in system scope

```bash
cmd_status() {
  if [[ "$PSM_SCOPE" == "system" ]]; then
    # Show systemd unit status
    systemctl list-units 'psm-*' --no-pager
    return
  fi

  # ... existing podman status logic ...
}
```

### 5. Remove cleans up Quadlet files

In `profile_remove()`, when system scope:

```bash
profile_remove() {
  # ... existing logic ...

  if [[ "$PSM_SCOPE" == "system" ]]; then
    local unit_name="psm-${network}-${asset_name}"
    systemctl disable "$unit_name" 2>/dev/null || true
    systemctl stop "$unit_name" 2>/dev/null || true
    rm -f "/etc/containers/systemd/${unit_name}.container"
    rm -f "${instance_dir}/config/quadlet.env"
    systemctl daemon-reload
    echo "  Removed systemd unit: ${unit_name}"
  fi
}
```

## Test Spec

System scope tests require root on a Linux host with systemd. These cannot be tested on macOS.

### Single-container Quadlet

```bash
sudo psm install postgres --system
# Should create /etc/containers/systemd/psm-psm-postgres.container
cat /etc/containers/systemd/psm-psm-postgres.container
# Should contain [Container], [Service], [Install] sections

sudo psm up postgres --system
systemctl status psm-psm-postgres
# Should show active (running)

sudo psm down postgres --system
systemctl status psm-psm-postgres
# Should show inactive

sudo psm remove postgres --system
# Should remove Quadlet file and disable unit
ls /etc/containers/systemd/psm-psm-postgres.container
# Should not exist
```

### Dependency ordering in systemd

```bash
sudo psm install gatekeeper --system
cat /etc/containers/systemd/psm-gatekeeper-postgres.container | grep After
# Should show no After (leaf dependency)

# Note: gatekeeper itself has no compose.yml, so no Quadlet generated for it.
# postgres and redis get Quadlets with appropriate ordering.
```

### Multi-container warning

```bash
# If a service has multiple containers in compose.yml:
sudo psm install authentik --system
# Should warn: "authentik has multiple containers — Quadlet not generated, use podman-compose"
```

## Verification

- [ ] `_generate_quadlet()` exists and generates valid `.container` files
- [ ] Quadlet files include `After=`/`Requires=` for dependencies
- [ ] `psm install postgres --system` creates Quadlet file in `/etc/containers/systemd/`
- [ ] `psm up postgres --system` delegates to `systemctl start`
- [ ] `psm down postgres --system` delegates to `systemctl stop`
- [ ] `psm status --system` shows systemd unit status
- [ ] `psm remove postgres --system` removes Quadlet file and disables unit
- [ ] User scope (`--user`) is completely unaffected — still uses podman-compose
- [ ] Multi-container services produce a warning and skip Quadlet generation
- [ ] Env file for Quadlet is written to `config/quadlet.env` (persistent, not tempfile)
