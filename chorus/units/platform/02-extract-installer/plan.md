---
---

# Plan 02 — Extract Installer and Stow Backend

## Context — read these files first

- `ppm` — `installer()` function (~60 lines), `remover()` function (~40 lines), `install()` entry point, `remove()` entry point
- `lib/stow.sh` — `stow_subdir()`, `package_links()`, `force_remove_conflicts()`
- `lib/meta.sh` — `meta_mark_installed()`, `meta_cleanup_stale()`, `meta_mark_removed()`
- Plan 01 output: env var bootstrap, `collect_assets()`, backend lib sourcing

## Overview

Extract `installer()` and `remover()` from the main ppm script into `lib/installer.sh` as the generic orchestrator. Extract the stow-specific install/remove logic into `lib/packages/stow.sh` which defines `profile_install()` and `profile_remove()`. The installer calls the profile functions instead of inline stow code.

After this plan, the installer is backend-agnostic. Adding a new backend (services) only requires creating `lib/services/` with its own `profile_install()`.

## Implementation

### 1. Create `lib/packages/stow.sh`

This file defines the package backend's install and remove behaviors. Extract from the current `installer()` function:

```bash
#!/usr/bin/env bash
# Package backend — stow-based dotfile management

# Install a package asset: stow its home/ directory into $HOME
# Called by the generic installer after pre_install and before post_install
# Arguments: asset_dir asset_name
profile_install() {
  local asset_dir="$1" asset_name="$2"

  stow_subdir "$asset_dir" "home"
  [[ -n "${PPM_GROUP_ID:-}" ]] && stow_subdir "$asset_dir" "$PPM_GROUP_ID"

  # Collect stowed file list for tracking
  local stowed_files=""
  [[ -d "$asset_dir/home" ]] && stowed_files=$(package_links "$asset_dir/home")
  if [[ -n "${PPM_GROUP_ID:-}" && -d "$asset_dir/$PPM_GROUP_ID" ]]; then
    local group_files
    group_files=$(package_links "$asset_dir/$PPM_GROUP_ID")
    [[ -n "$group_files" ]] && stowed_files="${stowed_files}"$'\n'"${group_files}"
  fi

  # Return stowed files via global (subshell-safe alternative to return values)
  PROFILE_STOWED_FILES="$stowed_files"
}

# Remove a package asset: unstow its home/ directory from $HOME
# Called by the generic remover after pre_remove and before post_remove
# Arguments: asset_dir asset_name
profile_remove() {
  local asset_dir="$1" asset_name="$2"

  [[ -d "$asset_dir/home" ]] && stow -D -d "$asset_dir" -t "$HOME" home
  [[ -n "${PPM_GROUP_ID:-}" && -d "$asset_dir/$PPM_GROUP_ID" ]] && \
    stow -D -d "$asset_dir" -t "$HOME" "$PPM_GROUP_ID"
}
```

### 2. Create `lib/installer.sh`

Move `installer()` and `remover()` from the main ppm script. Refactor to use `$PPM_ASSET_DIR`, `$PPM_ASSET_HOOK`, and `profile_install()`/`profile_remove()`:

```bash
#!/usr/bin/env bash
# Generic asset installer/remover — backend-agnostic

installer() {
  collect_repos
  requested_assets=("$@")

  for asset in "${requested_assets[@]}"; do
    local asset_repo=$(dirname "$asset") asset_name=$(basename "$asset")
    [[ "$asset" == */* ]] && single_repo="true" || single_repo="false"

    for i in "${!REPO_URLS[@]}"; do
      local repo_name="${REPO_NAMES[$i]}"
      [[ "$single_repo" == "true" && "$repo_name" != "$asset_repo" ]] && continue

      asset_dir="$PPM_DATA_HOME/$repo_name/$PPM_ASSET_DIR/$asset_name"
      [[ ! -d "$asset_dir" ]] && continue
      debug "Found $asset_name in repo $repo_name"
      PPM_CURRENT_PACKAGE="$repo_name/$asset_name"
      echo "Install $repo_name/$asset_name"

      # No hook script — just run profile install, track, and continue
      if [[ ! -f "$asset_dir/$PPM_ASSET_HOOK" ]]; then
        PROFILE_STOWED_FILES=""
        profile_install "$asset_dir" "$asset_name"
        meta_cleanup_stale "$repo_name" "$asset_name" "$asset_dir" "$PROFILE_STOWED_FILES"
        meta_mark_installed "$repo_name" "$asset_name" "$asset_dir" "$PROFILE_STOWED_FILES"
        continue
      fi

      # Handle dependencies
      if ! $skip_deps; then
        local deps
        deps=$(resolve_package_deps "$asset_dir")
        if [[ -n "$deps" ]]; then
          for dep in $deps; do
            debug "Dependency: $asset_name requires $dep"
            "$0" "installer" ${config_flag:+"$config_flag"} ${force_flag:+"$force_flag"} ${skip_deps_flag:+"$skip_deps_flag"} "$dep"
          done
        fi
      fi

      # pre_install hook
      (
        source "$asset_dir/$PPM_ASSET_HOOK"
        if type pre_install &>/dev/null && [[ -z "$config_flag" ]]; then
          pre_install
        fi
      )

      # Profile-specific install step
      PROFILE_STOWED_FILES=""
      profile_install "$asset_dir" "$asset_name"

      # Clean up stale files from previous version
      meta_cleanup_stale "$repo_name" "$asset_name" "$asset_dir" "$PROFILE_STOWED_FILES"

      # Post-install and OS-specific install
      (
        source "$asset_dir/$PPM_ASSET_HOOK"

        func_name="install_$(os)"
        if type $func_name &>/dev/null && [[ -z "$config_flag" ]]; then
          $func_name
        fi

        if type post_install &>/dev/null && [[ -z "$config_flag" ]]; then
          post_install
        fi
      )

      # Write tracker
      meta_mark_installed "$repo_name" "$asset_name" "$asset_dir" "$PROFILE_STOWED_FILES"
    done
  done
}


remover() {
  collect_repos
  requested_assets=("$@")

  for asset in "${requested_assets[@]}"; do
    local asset_repo=$(dirname "$asset") asset_name=$(basename "$asset")
    [[ "$asset" == */* ]] && single_repo="true" || single_repo="false"

    for i in "${!REPO_URLS[@]}"; do
      local repo_name="${REPO_NAMES[$i]}"
      [[ "$single_repo" == "true" && "$repo_name" != "$asset_repo" ]] && continue

      local asset_dir="$PPM_DATA_HOME/$repo_name/$PPM_ASSET_DIR/$asset_name"
      [[ ! -d "$asset_dir" ]] && continue
      echo "Remove $repo_name/$asset_name"

      local has_hook
      [[ -f "$asset_dir/$PPM_ASSET_HOOK" ]] && has_hook=true || has_hook=false

      # pre_remove hook
      if $has_hook; then
        (
          source "$asset_dir/$PPM_ASSET_HOOK"
          type pre_remove &>/dev/null && pre_remove || true
        )
      fi

      # Profile-specific remove step
      profile_remove "$asset_dir" "$asset_name"

      # OS-specific remove + post_remove
      if $has_hook; then
        (
          source "$asset_dir/$PPM_ASSET_HOOK"
          func_name="remove_$(os)"
          type $func_name &>/dev/null && $func_name || true
          type post_remove &>/dev/null && post_remove || true
        )
      fi

      # Remove tracker
      meta_mark_removed "$repo_name" "$asset_name"
    done
  done
}
```

### 3. Update the main ppm script

Remove the `installer()` and `remover()` function bodies from the main script. They now come from `lib/installer.sh` (sourced via the `lib/*.sh` glob).

The `install()` and `remove()` entry points remain in the main script — they handle flag parsing, call `expand_packages`, then delegate to `installer`/`remover`.

### 4. Verify function resolution order

Sourcing order matters. After plan 01, the order is:
1. `lib/*.sh` (shared libs including `installer.sh`)
2. `lib/$PPM_ASSET_DIR/*.sh` (backend libs including `packages/stow.sh`)

`installer.sh` references `profile_install()` which is defined in `packages/stow.sh`. Since `lib/packages/*.sh` is sourced after `lib/*.sh`, the function is available when `installer()` is actually called (at command dispatch time, not at source time). This is fine — bash resolves function names at call time, not definition time.

### 5. Handle edge case: no backend libs

If `lib/$PPM_ASSET_DIR/` doesn't exist (e.g., someone passes `PPM_ASSET_DIR=widgets` without creating the backend), `profile_install` won't be defined. Add a fallback in `installer.sh`:

```bash
# Default profile_install — no-op if no backend loaded
if ! type profile_install &>/dev/null; then
  profile_install() {
    debug "No profile_install defined for asset dir '$PPM_ASSET_DIR' — skipping"
    PROFILE_STOWED_FILES=""
  }
fi

if ! type profile_remove &>/dev/null; then
  profile_remove() {
    debug "No profile_remove defined for asset dir '$PPM_ASSET_DIR' — skipping"
  }
fi
```

Place this at the bottom of `installer.sh` — it will be overridden if a backend defines the functions.

Actually, the backend is sourced AFTER `installer.sh`, so the backend's definitions naturally override. The fallbacks in `installer.sh` only fire if no backend is loaded. This is correct.

## Test Spec

### Identical behavior

```bash
# Before and after, these must produce identical results:
ppm list
ppm list --installed
ppm install -r zsh           # reinstall
ppm show zsh
ppm remove pde-ppm/zsh       # remove, then reinstall
ppm install zsh
```

### File structure

```bash
ls -la ~/.local/share/ppm/ppm/lib/installer.sh    # exists
ls -la ~/.local/share/ppm/ppm/lib/packages/stow.sh # exists
```

### Functions defined

```bash
# In a debug session or by adding a test command:
type profile_install   # should show it's defined
type profile_remove    # should show it's defined
type installer         # should show it's from lib/installer.sh context
```

## Verification

- [ ] `lib/installer.sh` exists with `installer()` and `remover()` functions
- [ ] `lib/packages/stow.sh` exists with `profile_install()` and `profile_remove()`
- [ ] `lib/packages/` directory is created
- [ ] `installer()` and `remover()` function bodies removed from main `ppm` script
- [ ] `install()` and `remove()` entry points remain in main script, delegate to `installer()`/`remover()`
- [ ] `ppm install zsh` works — package is stowed correctly
- [ ] `ppm remove pde-ppm/zsh` works — package is unstowed correctly
- [ ] `ppm install -r zsh` works — reinstall stows correctly
- [ ] `ppm install rails` works — dependencies resolved and installed in order
- [ ] `ppm list --installed` shows correct tracking data
- [ ] No references to `stow_subdir` or `stow -D` remain in main `ppm` script or `lib/installer.sh`
