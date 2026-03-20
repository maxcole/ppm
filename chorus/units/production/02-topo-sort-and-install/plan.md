---
---

# Plan 02 — Topological Sort & Installer Rewrite

## Context — read these files first

- `ppm` — `install()`, `installer()` functions
- `lib/graph.sh` — `resolve_deps()`, `RESOLVE_ORDER`, `RESOLVED_PACKAGES` (from plan 01)
- `lib/stow.sh` — `stow_subdir()`, `force_remove_conflicts()`
- `lib/meta.sh` — `meta_mark_installed()`

## Overview

Rewrite `install()` and `installer()` to use the dependency graph from plan 01. The new flow:

1. Expand requested packages (handle `repo/` syntax)
2. Resolve full dependency graph via `resolve_deps()`
3. `RESOLVE_ORDER` is already in topological order (depth-first produces leaves first)
4. Iterate `RESOLVE_ORDER` and install each package once, in order

This eliminates the recursive `"$0" "installer"` subprocess pattern entirely.

## Implementation

### 1. Rewrite `install()`

```bash
install() {
  [[ "$(os)" == "macos" ]] && update_brew_if_needed
  update_ppm_if_needed

  expand_packages "install" "$@"
  $reinstall && remover "${EXPANDED_PACKAGES[@]}"

  collect_repos

  # Resolve full dependency graph
  declare -A RESOLVED_PACKAGES
  declare -a RESOLVE_ORDER
  declare -A _RESOLVING

  if ! $skip_deps; then
    resolve_deps "${EXPANDED_PACKAGES[@]}"
  else
    # Skip deps mode: just resolve the requested packages, no transitive deps
    for pkg in "${EXPANDED_PACKAGES[@]}"; do
      local pkg_dir
      pkg_dir=$(find_package_dir "$pkg") || { echo "Error: Package '$pkg' not found"; exit 1; }
      local qualified="${FOUND_REPO_NAME}/${pkg##*/}"
      RESOLVED_PACKAGES["$qualified"]="$pkg_dir"
      RESOLVE_ORDER+=("$qualified")
    done
  fi

  echo "Installing ${#RESOLVE_ORDER[@]} package(s):"
  for pkg in "${RESOLVE_ORDER[@]}"; do
    echo "  $pkg"
  done
  echo ""

  # Install in topological order
  for qualified in "${RESOLVE_ORDER[@]}"; do
    local pkg_dir="${RESOLVED_PACKAGES[$qualified]}"
    local repo_name="${qualified%%/*}"
    local package_name="${qualified##*/}"

    install_single_package "$repo_name" "$package_name" "$pkg_dir"
  done

  flush_user_messages
}
```

### 2. Extract `install_single_package()`

Pull the per-package install logic out of the current `installer()` loop into a standalone function. This is essentially the body of the inner `for repo` loop, minus the dependency handling:

```bash
install_single_package() {
  local repo_name="$1" package_name="$2" package_dir="$3"
  local ignore_args=()

  echo "Install $repo_name/$package_name"
  debug "Package dir: $package_dir"

  # No installer — just stow
  if [[ ! -f "$package_dir/install.sh" ]]; then
    stow_subdir "$package_dir" "home"
    [[ -n "${PPM_GROUP_ID:-}" ]] && stow_subdir "$package_dir" "$PPM_GROUP_ID"
    meta_mark_installed "$repo_name" "$package_name" "$package_dir"
    return
  fi

  # pre_install hook
  (
    source "$package_dir/install.sh"
    if type pre_install &>/dev/null && [[ -z "${config_flag:-}" ]]; then
      pre_install
    fi
  )

  # Stow (main shell for ignore_args persistence)
  stow_subdir "$package_dir" "home"
  [[ -n "${PPM_GROUP_ID:-}" ]] && stow_subdir "$package_dir" "$PPM_GROUP_ID"

  # OS-specific install + post_install
  (
    source "$package_dir/install.sh"

    local func_name="install_$(os)"
    if type "$func_name" &>/dev/null && [[ -z "${config_flag:-}" ]]; then
      "$func_name"
    fi

    if type post_install &>/dev/null && [[ -z "${config_flag:-}" ]]; then
      post_install
    fi
  )

  meta_mark_installed "$repo_name" "$package_name" "$package_dir"
}
```

### 3. Handle the `ignore_args` cross-repo stow issue

Currently, `ignore_args` accumulates across repos for the same package name (when a package exists in multiple repos). With the new flat install loop, each `install_single_package` call is for a single qualified `repo/package` — the `ignore_args` array is local to that call. The cross-repo stow conflict handling (where files stowed from repo A are ignored when stowing from repo B) is preserved because `resolve_deps` only resolves one repo per package name (first match wins).

### 4. Remove the old `installer()` function

The old `installer()` with its nested `for pkg / for repo` loops and recursive subprocess calls is fully replaced. Remove it.

### 5. Update `main()` dispatch

The `main()` case used to call `installer` directly for the recursive dep pattern. Now `install()` is the sole entry point. Verify that no code path calls `installer` directly (search for `"$0" "installer"` and `installer` function calls).

### 6. Verify `remove()` still works

`remove()` / `remover()` don't need the dependency graph — removal is per-package, not transitive. Leave `remover()` as-is for now.

## Test Spec

- `ppm install rails` → installs mise, ruby, rails in that order; each exactly once
- `ppm install claude ruby` → mise installed once (shared dep), before both
- `ppm install -s rails` → installs only rails, skips mise and ruby
- `ppm install pde-ppm/` → resolves all packages from pde-ppm with their deps, installs in order
- `ppm install -f rails` → force install (remove conflicts) works with new flow
- `ppm remove rails` → still works (remover unchanged)
- `ppm list --installed` → shows all packages installed during the above tests

## Verification

- [ ] Old `installer()` function is removed
- [ ] No `"$0" "installer"` recursive calls remain anywhere
- [ ] `install_single_package()` handles stow-only, pre_install, post_install, OS-specific install
- [ ] `ppm install rails` produces correct install order in output
- [ ] Shared dependencies installed exactly once
- [ ] `--debug` shows the full resolution and install sequence
- [ ] `-s` (skip-deps) still works
- [ ] `-f` (force) still works
- [ ] `-r` (reinstall) still works
- [ ] `-c` (config-only) still works
- [ ] `flush_user_messages` is called at the end
