---
---

# Plan 01 — Lib Extraction & Space Removal

## Context — read these files first

- `ppm` — the monolithic script to be split (~600 lines)
- `~/.config/ppm/ppm.conf` — current config (has `HOMEBREW_UPDATE_CACHE_DURATION`)
- `~/.config/ppm/sources.list` — current format (one URL per line)

## Overview

Split the monolithic `ppm` script into an entrypoint + library files under `lib/`. Also remove all deprecated space-related code from the install/remove flows.

The ppm script currently sources `$PPM_LIB_DIR/*.sh` (`~/.local/lib/ppm/*.sh`) — this is a runtime extension point where packages (like zsh) drop functions for cross-package use. This must be preserved. The new repo-local `lib/` directory is for ppm's own internal plumbing.

## Implementation

### 1. Create `lib/` directory in the ppm repo

### 2. Extract utility functions into `lib/core.sh`

Move these functions from `ppm` into `lib/core.sh`:
- `os()`
- `arch()`
- `add_to_file()`
- `remove_from_file()`
- `_string_in_file()`
- `_sed_inplace()`
- `create_symlinks()`
- `is_git_url()`

### 3. Extract brew functions into `lib/brew.sh`

Move:
- `update_brew_if_needed()`
- `install_dep()`

### 4. Extract repo functions into `lib/repo.sh`

Move:
- `collect_repos()`
- `collect_packages()`
- `is_repo_name()`
- `expand_packages()`

### 5. Extract stow functions into `lib/stow.sh`

Move:
- `stow_subdir()`
- `package_links()`
- `force_remove_conflicts()`

### 6. Create empty `lib/meta.sh`

Placeholder — will be populated in plan 03.

### 7. Update sourcing in `ppm` entrypoint

Replace the existing lib sourcing block with:

```bash
# Resolve the repo directory (works through symlinks)
PPM_REPO_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"

# Source ppm's own libraries
for lib_file in "$PPM_REPO_DIR"/lib/*.sh; do
  [[ -f "$lib_file" ]] && source "$lib_file"
done

# Source package-contributed libraries (e.g. from zsh package)
if [[ -d "$PPM_LIB_DIR" ]]; then
  for lib_file in "$PPM_LIB_DIR"/*.sh; do
    [[ -f "$lib_file" ]] && source "$lib_file"
  done
fi
```

Note: on macOS, `readlink -f` requires coreutils or we use a bash-native alternative:
```bash
_resolve_path() {
  local path="$1"
  while [[ -L "$path" ]]; do
    local dir="$(cd "$(dirname "$path")" && pwd)"
    path="$(readlink "$path")"
    [[ "$path" != /* ]] && path="$dir/$path"
  done
  echo "$(cd "$(dirname "$path")" && pwd)"
}
PPM_REPO_DIR="$(_resolve_path "$0")"
```

### 8. Remove space-related code from `ppm`

In `installer()`, remove the entire block:
```bash
if type "space_path" &>/dev/null; then
  ...
fi
```

In `remover()`, remove the block:
```bash
if type space_path &>/dev/null; then
  ...
fi
```

These blocks handle `space_path`, `space_install`, `space_remove`, and `stow -d $package_dir -t $(space_path) space`. All deprecated in favor of chorus — packages that need space setup use `chorus_init` in their own `post_install()`.

### 9. Remove `update_self()` from `ppm`

The `ppm update ppm` special case that curls a script from GitHub is no longer needed since ppm is now a cloned repo. Regular `ppm update` (git pull) handles updating the ppm repo itself since it's in sources.list.

Remove:
- The `update_self()` function
- The `if [[ $# -gt 0 && "$1" == "ppm" ]]; then update_self; return; fi` block in `update()`
- The `PPM_BIN_URL` variable

## Test Spec

Manual verification:
- `ppm list` works as before
- `ppm install <some-package>` works (stow + install.sh hooks fire)
- `ppm remove <some-package>` works
- `ppm show <package>` works
- No references to `space_path`, `space_install`, `space_remove` remain in `ppm`
- Package-contributed libs from `$PPM_LIB_DIR` still get sourced (verify by checking a function from zsh's lib is available)

## Verification

- [ ] `ppm` entrypoint is under 300 lines
- [ ] `lib/core.sh`, `lib/brew.sh`, `lib/repo.sh`, `lib/stow.sh` exist
- [ ] `grep -r 'space_path\|space_install\|space_remove' ppm` returns nothing
- [ ] `grep -r 'update_self\|PPM_BIN_URL' ppm` returns nothing
- [ ] All existing ppm commands work unchanged
