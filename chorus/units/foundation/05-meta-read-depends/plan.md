---
---

# Plan 05 — Meta Library & Depends from YAML

## Context — read these files first

- `ppm` — `installer()` function, specifically the dependencies/subshell block
- `lib/meta.sh` — empty placeholder (from plan 01)
- Any `package.yml` file created by plan 04 (e.g., `~/.local/share/ppm/pde-ppm/packages/claude/package.yml`)

## Overview

Populate `lib/meta.sh` with functions that read `package.yml` via `yq`. Modify `installer()` to use `meta_depends()` for dependency resolution instead of sourcing `dependencies()` from `install.sh`. Maintain backward compatibility for packages that haven't been migrated yet.

## Implementation

### 1. Populate `lib/meta.sh`

```bash
#!/usr/bin/env bash
# Package metadata functions — reads package.yml via yq

# Read the depends list from package.yml
# Returns one dependency per line (suitable for while-read loops)
# Usage: meta_depends <package_dir>
meta_depends() {
  local pkg_dir="$1"
  local meta="$pkg_dir/package.yml"
  [[ -f "$meta" ]] || return 0
  yq -r '.depends[]? // empty' "$meta" 2>/dev/null
}

# Read the version from package.yml
# Usage: meta_version <package_dir>
meta_version() {
  local pkg_dir="$1"
  local meta="$pkg_dir/package.yml"
  [[ -f "$meta" ]] || return 0
  yq -r '.version // empty' "$meta" 2>/dev/null
}

# Read the author from package.yml
# Usage: meta_author <package_dir>
meta_author() {
  local pkg_dir="$1"
  local meta="$pkg_dir/package.yml"
  [[ -f "$meta" ]] || return 0
  yq -r '.author // empty' "$meta" 2>/dev/null
}

# Get dependencies, falling back to install.sh if no package.yml
# Returns space-separated list (matching old dependencies() convention)
# Usage: resolve_package_deps <package_dir>
resolve_package_deps() {
  local pkg_dir="$1"
  local meta="$pkg_dir/package.yml"

  if [[ -f "$meta" ]] && yq -e '.depends' "$meta" &>/dev/null; then
    # Read from YAML, output space-separated
    yq -r '.depends[]' "$meta" 2>/dev/null | tr '\n' ' '
  elif [[ -f "$pkg_dir/install.sh" ]]; then
    # Fallback: source install.sh and call dependencies()
    (
      source "$pkg_dir/install.sh" 2>/dev/null
      type dependencies &>/dev/null && dependencies
    )
  fi
}
```

### 2. Modify `installer()` dependency block

Replace the current dependency handling in `installer()`:

**Before** (current code in the subshell):
```bash
(
  source "$package_dir/install.sh"
  if ! $skip_deps && type dependencies &>/dev/null; then
    deps=$(dependencies)
    for dep in $deps; do
      "$0" "installer" ${config_flag:+"$config_flag"} ${force_flag:+"$force_flag"} ${skip_deps_flag:+"$skip_deps_flag"} "$dep"
    done
  fi
  ...
)
```

**After**:
```bash
# Handle dependencies
if ! $skip_deps; then
  local deps
  deps=$(resolve_package_deps "$package_dir")
  if [[ -n "$deps" ]]; then
    for dep in $deps; do
      debug "Dependency: $package_name requires $dep"
      "$0" "installer" ${config_flag:+"$config_flag"} ${force_flag:+"$force_flag"} ${skip_deps_flag:+"$skip_deps_flag"} "$dep"
    done
  fi
fi

# pre_install hook (still needs sourcing install.sh)
if [[ -f "$package_dir/install.sh" ]]; then
  (
    source "$package_dir/install.sh"
    if type pre_install &>/dev/null && [[ -z "$config_flag" ]]; then
      pre_install
    fi
  )
fi
```

Key change: dependency resolution moves out of the subshell and uses `resolve_package_deps()` instead of sourcing `install.sh`. The `pre_install` hook stays in a subshell since it needs the sourced environment.

Note: This plan keeps the recursive `"$0" "installer"` pattern for now. The dependency graph (production tier) will replace it with a proper up-front resolution. This is the minimal change to read from YAML.

### 3. Update `show()` to read from `package.yml`

The `show()` function currently sources `install.sh` to get dependencies. Update it to use `resolve_package_deps()` first, fall back to the source approach:

```bash
# Show dependencies
local deps
deps=$(resolve_package_deps "$package_dir")
if [[ -n "$deps" ]]; then
  echo "Dependencies:"
  for dep in $deps; do
    echo "  - $dep"
  done
  echo ""
fi

# Show version
local version
version=$(meta_version "$package_dir")
if [[ -n "$version" ]]; then
  echo "Version: $version"
fi
```

## Test Spec

- `ppm show pde-ppm/claude` displays `depends: mise` (read from package.yml)
- `ppm show pde-ppm/tmux` displays no dependencies (no depends key in yaml)
- `ppm install claude` installs mise first (dep resolved from yaml)
- `ppm install rails` installs ruby first, which installs mise first (transitive deps from yaml)
- If a package has no `package.yml` but has `dependencies()` in install.sh, fallback works

## Verification

- [ ] `lib/meta.sh` contains `meta_depends`, `meta_version`, `meta_author`, `resolve_package_deps`
- [ ] `installer()` no longer sources `install.sh` just for `dependencies()`
- [ ] `show()` reads deps from `package.yml` first
- [ ] Backward compat: a package without `package.yml` still resolves deps from `install.sh`
- [ ] `yq` errors are handled gracefully (missing file, missing key)
