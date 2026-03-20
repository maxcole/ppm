---
---

# Plan 06 — Installed Package Tracking with Stale File Cleanup

## Context — read these files first

- `ppm` — `installer()` and `remover()` functions, `list()` function
- `lib/meta.sh` — `meta_version()` (from plan 05)
- `lib/stow.sh` — `stow_subdir()`, `package_links()` — these produce the file lists we'll track

## Overview

Track installed packages using a directory of per-package YAML files at `$PPM_DATA_HOME/.installed/<repo>/<package>.yml`. Each tracker records version, install timestamp, and the list of stowed files.

On reinstall or upgrade, the tracker enables detection and cleanup of stale files — files that were stowed by a previous version but no longer exist in the current version.

## Design

### Directory layout

```
$PPM_DATA_HOME/.installed/
  pde-ppm/
    git.yml
    zsh.yml
    claude.yml
  pdt-ppm/
    node.yml
    solana.yml
  rjayroach-ppm/
    git.yml
```

### Tracker file format (e.g., `pde-ppm/git.yml`)

```yaml
version: 0.1.0
installed_at: "2026-03-16T10:00:00Z"
files:
  - .config/git/config
  - .config/git/ignore
  - .config/git/attributes
```

`files` contains the relative paths from `$HOME` — exactly what `package_links()` returns for the `home/` (and group) directories.

### Install flow — stale file cleanup

When installing a package that already has a tracker file:

1. Read old tracker → get `old_files` list
2. Run stow as normal (the current `stow_subdir` calls)
3. Collect `new_files` from `package_links()` for the directories that were stowed
4. Compute `stale_files = old_files - new_files`
5. For each stale file: check that `$HOME/<file>` is a symlink pointing into this package's directory. If so, remove it. If it's a real file or points elsewhere (higher-priority repo override, user-created), leave it alone.
6. Write new tracker file with `new_files`, version, timestamp

The symlink target check in step 5 is critical — it prevents removing files that belong to another repo or were manually placed by the user.

### Remove flow

1. Read tracker → get `files` list
2. Run `stow -D` as currently (unstow)
3. Delete the tracker file
4. Optionally remove empty parent directory under `.installed/`

## Implementation

### 1. Add tracker functions to `lib/meta.sh`

```bash
PPM_INSTALLED_DIR="$PPM_DATA_HOME/.installed"

# Path to a package's tracker file
# Usage: _tracker_path <repo_name> <package_name>
_tracker_path() {
  echo "$PPM_INSTALLED_DIR/$1/$2.yml"
}

# Record a package as installed with its stowed file list
# Usage: meta_mark_installed <repo_name> <package_name> <package_dir> <files...>
# files are passed as a newline-separated string
meta_mark_installed() {
  local repo_name="$1" pkg_name="$2" pkg_dir="$3" stowed_files="$4"
  local tracker
  tracker=$(_tracker_path "$repo_name" "$pkg_name")
  local version
  version=$(meta_version "$pkg_dir")
  [[ -z "$version" ]] && version="unknown"

  local timestamp
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  mkdir -p "$(dirname "$tracker")"

  # Build the YAML
  {
    echo "version: $version"
    echo "installed_at: \"$timestamp\""
    if [[ -n "$stowed_files" ]]; then
      echo "files:"
      echo "$stowed_files" | while IFS= read -r f; do
        [[ -n "$f" ]] && echo "  - $f"
      done
    fi
  } > "$tracker"
}

# Read previously stowed files from tracker
# Usage: meta_installed_files <repo_name> <package_name>
# Outputs one file per line
meta_installed_files() {
  local tracker
  tracker=$(_tracker_path "$1" "$2")
  [[ -f "$tracker" ]] || return 0
  yq -r '.files[]? // empty' "$tracker" 2>/dev/null
}

# Remove the tracker file for a package
# Usage: meta_mark_removed <repo_name> <package_name>
meta_mark_removed() {
  local tracker
  tracker=$(_tracker_path "$1" "$2")
  rm -f "$tracker"
  # Clean up empty repo directory
  local repo_dir="$PPM_INSTALLED_DIR/$1"
  [[ -d "$repo_dir" ]] && rmdir "$repo_dir" 2>/dev/null || true
}

# Check if a package is installed (tracker exists)
# Usage: meta_is_installed <repo_name> <package_name>
meta_is_installed() {
  local tracker
  tracker=$(_tracker_path "$1" "$2")
  [[ -f "$tracker" ]]
}

# Get installed version of a package
# Usage: meta_installed_version <repo_name> <package_name>
meta_installed_version() {
  local tracker
  tracker=$(_tracker_path "$1" "$2")
  [[ -f "$tracker" ]] || return 0
  yq -r '.version // empty' "$tracker" 2>/dev/null
}

# Remove stale files left over from a previous install
# Compares old tracked files against new file list,
# only removes symlinks that point into the given package dir
# Usage: meta_cleanup_stale <repo_name> <package_name> <package_dir> <new_files>
meta_cleanup_stale() {
  local repo_name="$1" pkg_name="$2" pkg_dir="$3" new_files="$4"
  local tracker
  tracker=$(_tracker_path "$repo_name" "$pkg_name")
  [[ -f "$tracker" ]] || return 0

  local old_files
  old_files=$(meta_installed_files "$repo_name" "$pkg_name")
  [[ -z "$old_files" ]] && return 0

  while IFS= read -r old_file; do
    [[ -z "$old_file" ]] && continue

    # Skip if file is in the new set
    if echo "$new_files" | grep -qxF "$old_file"; then
      continue
    fi

    local target="$HOME/$old_file"

    # Only remove if it's a symlink pointing into this package's directory
    if [[ -L "$target" ]]; then
      local link_dest
      link_dest=$(readlink "$target")
      if [[ "$link_dest" == *"$pkg_dir"* ]]; then
        debug "Removing stale file: $old_file"
        rm -f "$target"
      else
        debug "Skipping stale file (owned by another source): $old_file"
      fi
    else
      debug "Skipping stale file (not a symlink): $old_file"
    fi
  done <<< "$old_files"
}
```

### 2. Collect stowed files during install

The `stow_subdir` / `package_links` functions already compute the file list. We need to capture it during `installer()`.

In `installer()`, after the stow phase, collect the files that were stowed:

```bash
# After stow_subdir calls, collect the full file list for tracking
local stowed_files=""
[[ -d "$package_dir/home" ]] && stowed_files=$(package_links "$package_dir/home")
if [[ -n "${PPM_GROUP_ID:-}" && -d "$package_dir/$PPM_GROUP_ID" ]]; then
  local group_files
  group_files=$(package_links "$package_dir/$PPM_GROUP_ID")
  [[ -n "$group_files" ]] && stowed_files="${stowed_files}"$'\n'"${group_files}"
fi
```

### 3. Integrate stale cleanup into install flow

In `installer()`, the sequence for each package becomes:

```bash
# 1. Stow (existing code)
stow_subdir "$package_dir" "home"
[[ -n "${PPM_GROUP_ID:-}" ]] && stow_subdir "$package_dir" "$PPM_GROUP_ID"

# 2. Collect what was just stowed
local stowed_files=""
[[ -d "$package_dir/home" ]] && stowed_files=$(package_links "$package_dir/home")
if [[ -n "${PPM_GROUP_ID:-}" && -d "$package_dir/$PPM_GROUP_ID" ]]; then
  local group_files
  group_files=$(package_links "$package_dir/$PPM_GROUP_ID")
  [[ -n "$group_files" ]] && stowed_files="${stowed_files}"$'\n'"${group_files}"
fi

# 3. Clean up stale files from previous version
meta_cleanup_stale "$repo_name" "$package_name" "$package_dir" "$stowed_files"

# ... (post_install hooks, OS-specific install) ...

# 4. Write tracker (at the very end, after all phases succeed)
meta_mark_installed "$repo_name" "$package_name" "$package_dir" "$stowed_files"
```

### 4. Update `remover()` to delete tracker

After unstow + post_remove:

```bash
meta_mark_removed "$repo_name" "$package_name"
```

### 5. Update `list()` to support `--installed`

```bash
list() {
  local filter="${1:-}" installed_only=false

  if [[ "$filter" == "--installed" ]]; then
    installed_only=true
    filter="${2:-}"
  fi

  if $installed_only; then
    if [[ ! -d "$PPM_INSTALLED_DIR" ]]; then
      echo "No packages installed (or tracking not yet enabled)"
      return
    fi
    for tracker in "$PPM_INSTALLED_DIR"/*/*.yml; do
      [[ -f "$tracker" ]] || continue
      local pkg_name="${tracker%.yml}"
      pkg_name="${pkg_name#$PPM_INSTALLED_DIR/}"  # e.g., "pde-ppm/git"
      local version
      version=$(yq -r '.version // "?"' "$tracker" 2>/dev/null)
      local line="$pkg_name  $version"
      if [[ -z "$filter" ]] || [[ "$line" == *"$filter"* ]]; then
        echo "$line"
      fi
    done
    return
  fi

  # Existing list behavior
  collect_packages
  for pkg in "${PACKAGES[@]}"; do
    if [[ -z "$filter" ]] || [[ "$pkg" == *"$filter"* ]]; then
      echo "$pkg"
    fi
  done
}
```

### 6. Update `show()` to include installed status

After displaying version and dependencies:

```bash
if meta_is_installed "$repo_name" "$package_name"; then
  local inst_version
  inst_version=$(meta_installed_version "$repo_name" "$package_name")
  echo "Status: installed (v${inst_version})"
  
  local inst_files
  inst_files=$(meta_installed_files "$repo_name" "$package_name")
  if [[ -n "$inst_files" ]]; then
    echo ""
    echo "Stowed files:"
    echo "$inst_files" | while IFS= read -r f; do
      [[ -n "$f" ]] && echo "  ~/$f"
    done
  fi
else
  echo "Status: not installed"
fi
```

## Test Spec

### Basic tracking
- `ppm install pde-ppm/git` → creates `$PPM_DATA_HOME/.installed/pde-ppm/git.yml` with version, timestamp, and file list
- `ppm remove pde-ppm/git` → deletes the tracker file
- `ppm list --installed` → lists installed packages with versions
- `ppm list --installed git` → filters to packages matching "git"
- `ppm show pde-ppm/git` → shows "Status: installed (v0.1.0)" and stowed file list

### Stale file cleanup
1. Install a package that stows files A, B, C
2. Manually verify tracker lists A, B, C
3. Remove file B from the package's `home/` directory (simulating a version change)
4. Reinstall the package
5. Verify: A and C are stowed, B is removed from `$HOME`, tracker now lists only A and C
6. Verify: if B was replaced with a real file (not a symlink) at `$HOME/B`, it is NOT removed

### Reinstall
- `ppm install pde-ppm/git` twice → tracker timestamp updates, file list refreshes

### Edge cases
- Package with no `home/` directory (install hooks only) → tracker has empty or missing `files` list
- Package in multiple repos → each repo's package gets its own tracker

## Verification

- [ ] `$PPM_DATA_HOME/.installed/` directory structure is created correctly
- [ ] Tracker files contain version, installed_at, and files list
- [ ] `meta_mark_installed` writes tracker with stowed file list
- [ ] `meta_mark_removed` deletes tracker and cleans empty parent dirs
- [ ] `meta_is_installed` checks for tracker file existence
- [ ] `meta_installed_files` returns the file list from tracker
- [ ] `meta_cleanup_stale` removes only symlinks pointing into the package dir
- [ ] `meta_cleanup_stale` skips real files and symlinks owned by other repos
- [ ] `ppm list --installed` scans `.installed/` directory
- [ ] `ppm show` displays installed status and stowed files
- [ ] Stale files are cleaned up on reinstall when package contents change
- [ ] No tracker file references `.installed.yml` (old single-file design removed)
