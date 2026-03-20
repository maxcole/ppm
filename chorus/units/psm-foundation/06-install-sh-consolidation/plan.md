---
---

# Plan 06 — Install Script Consolidation

## Context — read these files first

- `install.sh` — current ppm bootstrap installer
- `packages/psm/install.sh` — psm package hook that creates psm config dirs (platform plan 03)
- `docs/adr/001-ppm-as-configurable-engine.md` — single install.sh decision

## Overview

Consolidate the bootstrap installer (`install.sh`) to support both ppm and psm setup from a single script. The installer handles system dependency installation, ppm engine setup, and optionally bootstraps psm by installing the psm package.

This is the final plan in the psm-foundation tier. After this, a fresh machine can go from zero to running services with:

```bash
curl -fsSL <raw-url>/install.sh | bash -s -- --with-psm
```

## Implementation

### 1. Read the current install.sh

The current installer:
- Installs deps (Homebrew on macOS, sudo/git/stow/yq on Linux)
- Clones ppm repo to `~/.local/share/ppm/ppm`
- Copies ppm script to `~/.local/bin/ppm`
- Creates config dirs and default sources.list
- Runs `ppm update` and `ppm install` for specified packages

### 2. Add flags

```bash
# New flags:
#   --with-psm          Install psm package after ppm setup
#   --psm-repo URL      PSM service repo (added to psm sources.list)
#   --psm-only          Skip ppm package install, only set up psm
```

### 3. Dependency installation

Add `podman` and `podman-compose` to the dependency install phase, gated behind `--with-psm`:

```bash
install_deps() {
  # ... existing git, stow, yq install ...

  if $with_psm; then
    case "$(uname -s)" in
      Darwin)
        brew install podman podman-compose
        ;;
      Linux)
        sudo apt-get install -y podman podman-compose
        ;;
    esac
  fi
}
```

### 4. PSM bootstrap

After the standard ppm setup, if `--with-psm`:

```bash
if $with_psm; then
  echo "Setting up PSM..."

  # Install the psm package (creates config dirs, stows psm.zsh)
  ppm install psm

  # Add custom service repo if specified
  if [[ -n "$psm_repo" ]]; then
    PSM_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}/psm" \
    PPM_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}/psm" \
    PPM_ASSET_DIR=services \
    PPM_ASSET_HOOK=service.sh \
    PPM_ASSET_LABEL=service \
    ppm src add --top "$psm_repo"
  fi

  # Update service repos
  PSM_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}/psm" \
  PPM_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}/psm" \
  PPM_ASSET_DIR=services \
  ppm update

  echo "PSM ready. Open a new shell, then: psm list"
fi
```

### 5. Portability

The combined install should work for machine migration:

```bash
# Full setup on new machine:
export PPM_INSTALL_REPO=git@github.com:user/my-ppm
curl -fsSL <url>/install.sh | bash -s -- --with-psm --psm-repo git@github.com:user/my-psm-repo

# Or via env vars:
export PPM_INSTALL_REPO=git@github.com:user/my-ppm
export PSM_INSTALL_REPO=git@github.com:user/my-psm-repo
export PPM_INSTALL_PACKAGES="zsh vim tmux"
curl -fsSL <url>/install.sh | bash -s -- --with-psm
```

### 6. Update README

Update the main README to document the combined install flow and PSM setup.

## Test Spec

### Basic install (no psm)

```bash
# Existing behavior unchanged:
bash install.sh --script-only
which ppm    # should exist
```

### Install with psm

```bash
bash install.sh --with-psm --script-only
# Should install ppm, then ppm install psm
ls ~/.config/psm/sources.list    # should exist
```

### Install with custom psm repo

```bash
bash install.sh --with-psm --psm-repo /tmp/test-psm-repo --script-only
grep test-psm-repo ~/.config/psm/sources.list   # should be present
```

### Full flow on clean machine

```bash
# On a fresh Debian VM or macOS:
bash install.sh --with-psm
# Open new shell
psm list           # should show services from default psm-ppm repo
psm install postgres
psm up postgres
psm status         # postgres running
```

## Verification

- [ ] `install.sh --with-psm` installs podman + podman-compose
- [ ] `install.sh --with-psm` runs `ppm install psm`
- [ ] `~/.config/psm/sources.list` is created with default source
- [ ] `install.sh --with-psm --psm-repo URL` adds custom repo to psm sources
- [ ] `install.sh` without `--with-psm` behaves identically to current installer
- [ ] `install.sh --skip-deps --with-psm` skips podman install
- [ ] Fresh machine flow works: install → new shell → psm list → psm install → psm up
- [ ] README documents the combined install
