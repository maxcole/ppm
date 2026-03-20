---
---

# Plan 03 — PSM Package and Shell Function

## Context — read these files first

- `packages/ppm/home/.config/zsh/ppm.zsh` — existing ppm zsh wrapper (handles `ppm cd` and `zsrc` after install)
- `packages/ppm/package.yml` — ppm package metadata
- `packages/ppm/install.sh` — ppm package install hooks
- Plan 01 output: env var bootstrap with `PPM_CONFIG_HOME`, `PPM_DATA_HOME`, `PPM_ASSET_DIR`, `PPM_ASSET_HOOK`, `PPM_ASSET_LABEL`
- Plan 02 output: extracted installer with `profile_install()`/`profile_remove()` pattern

## Overview

Create a `psm` package in the ppm repo that, when installed via `ppm install psm`, stows a `psm()` zsh shell function. This function sets the PSM-specific environment variables and calls the ppm engine. The package's install hook creates the `~/.config/psm/` directory and a default `sources.list`.

This plan does NOT create the service backend libraries or any service repos. It only creates the entry point so that `psm list`, `psm update`, `psm src` etc. work (pointing at an empty or not-yet-populated service source list). Service-specific commands (up, down, logs, etc.) will fail gracefully with "unknown command" until the service backend is added in the PSM foundation tier.

## Implementation

### 1. Create `packages/psm/package.yml`

```yaml
version: 0.1.0
author: rjayroach
depends:
  - ppm
```

The `psm` package depends on `ppm` (to ensure the engine and ppm zsh function are installed first).

### 2. Create `packages/psm/home/.config/zsh/psm/psm.zsh`

```zsh
# psm.zsh — Podman Service Manager shell function
# Sets PSM-specific env vars and delegates to the ppm engine

if ! command -v ppm >/dev/null 2>&1; then
  return
fi

psm() {
  if [[ "${1:-}" == "cd" ]]; then
    shift
    local verbose_flag=""
    [[ "${1:-}" == "-v" ]] && { verbose_flag="-v"; shift; }
    if [[ $# -eq 0 ]]; then
      cd "${XDG_DATA_HOME:-$HOME/.local/share}/psm"
    else
      local svc_path
      svc_path=$(
        PPM_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}/psm" \
        PPM_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}/psm" \
        PPM_ASSET_DIR="services" \
        command ppm path $verbose_flag "$@"
      ) || return $?
      cd "$svc_path"
    fi
  else
    PPM_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}/psm" \
    PPM_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}/psm" \
    PPM_ASSET_DIR="services" \
    PPM_ASSET_HOOK="service.sh" \
    PPM_ASSET_LABEL="service" \
    command ppm "$@"
  fi
}
```

Note: No `zsrc` after install/remove for services — that's a package-specific behavior. The ppm zsh function retains its `zsrc` call; the psm function does not need it.

### 3. Create `packages/psm/install.sh`

```bash
#!/usr/bin/env bash

post_install() {
  local psm_config="${XDG_CONFIG_HOME:-$HOME/.config}/psm"
  local psm_data="${XDG_DATA_HOME:-$HOME/.local/share}/psm"

  # Create PSM config directory
  mkdir -p "$psm_config"

  # Create default sources.list if it doesn't exist
  if [[ ! -f "$psm_config/sources.list" ]]; then
    cat > "$psm_config/sources.list" <<'EOF'
# PSM service sources
# Format: <git-url>  <alias>
# Add repos with: psm src add <git-url>
EOF
    user_message "Created $psm_config/sources.list\\nAdd service repos with: psm src add <git-url>"
  fi

  # Create PSM data directory
  mkdir -p "$psm_data"

  # Create PSM services directory
  mkdir -p "$psm_data/services"
}
```

### 4. Update `packages/ppm/home/.config/zsh/ppm.zsh`

Minor update — ensure the ppm function doesn't interfere with psm. The current function intercepts `ppm cd` and adds `zsrc` after install. No changes needed to the logic, but verify that when the engine is called with PSM env vars (via the psm function), the ppm zsh wrapper isn't in the call path (it isn't — `psm()` calls `command ppm`, bypassing the `ppm()` function).

One optional improvement: add a comment noting that psm.zsh follows the same pattern.

### 5. Verify the sources.list bootstrap

When `psm src list` is called and `sources.list` exists but has no repo entries (only comments), the engine should handle this gracefully — no repos found, empty list output. Verify this works with the current `src list` implementation in the main ppm script.

## Test Spec

### Package installs

```bash
ppm install psm
# Should: stow psm.zsh, create ~/.config/psm/, create ~/.local/share/psm/
```

### Shell function works

```bash
# After zsrc or new shell:
which psm                    # should show it's a shell function
psm src list                 # should show empty or comment-only sources
psm list                     # should show no services (empty sources)
psm update                   # should handle no repos gracefully
```

### PSM data isolation

```bash
# PSM and PPM use separate data directories:
ls ~/.local/share/ppm/       # ppm repos
ls ~/.local/share/psm/       # psm services dir (empty)
ls ~/.config/ppm/            # ppm config
ls ~/.config/psm/            # psm config
```

### Engine receives correct env vars

```bash
# With --debug:
psm --debug list 2>&1 | head -20
# Should show PSM-specific paths in debug output
```

### ppm unaffected

```bash
# ppm still works as before:
ppm list
ppm install -r zsh
```

## Verification

- [ ] `packages/psm/package.yml` exists with `depends: [ppm]`
- [ ] `packages/psm/home/.config/zsh/psm/psm.zsh` exists with `psm()` function
- [ ] `packages/psm/install.sh` exists with `post_install()` that creates PSM config/data dirs
- [ ] `ppm install psm` succeeds
- [ ] `psm` shell function is available after shell reload
- [ ] `~/.config/psm/sources.list` is created
- [ ] `~/.local/share/psm/` is created
- [ ] `psm list` runs without error (empty output is fine)
- [ ] `psm src list` runs without error
- [ ] `ppm list` still works correctly
- [ ] `ppm install zsh` still works correctly
