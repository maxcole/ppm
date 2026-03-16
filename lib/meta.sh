#!/usr/bin/env bash
# Package metadata functions — reads package.yml via yq

PPM_INSTALLED_DIR="$PPM_DATA_HOME/.installed"

# Read the depends list from package.yml
# Returns one dependency per line (suitable for while-read loops)
# Usage: meta_depends <package_dir>
meta_depends() {
  local pkg_dir="$1"
  local meta="$pkg_dir/package.yml"
  [[ -f "$meta" ]] || return 0
  yq -r '.depends[]? // ""' "$meta" 2>/dev/null
}

# Read the version from package.yml
# Usage: meta_version <package_dir>
meta_version() {
  local pkg_dir="$1"
  local meta="$pkg_dir/package.yml"
  [[ -f "$meta" ]] || return 0
  yq -r '.version // ""' "$meta" 2>/dev/null
}

# Read the author from package.yml
# Usage: meta_author <package_dir>
meta_author() {
  local pkg_dir="$1"
  local meta="$pkg_dir/package.yml"
  [[ -f "$meta" ]] || return 0
  yq -r '.author // ""' "$meta" 2>/dev/null
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
      type dependencies &>/dev/null && dependencies || true
    )
  fi
}

# --- Installed package tracking ---

# Path to a package's tracker file
_tracker_path() {
  echo "$PPM_INSTALLED_DIR/$1/$2.yml"
}

# Record a package as installed with its stowed file list
# Usage: meta_mark_installed <repo_name> <package_name> <package_dir> <files>
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
meta_installed_files() {
  local tracker
  tracker=$(_tracker_path "$1" "$2")
  [[ -f "$tracker" ]] || return 0
  yq -r '.files[]? // ""' "$tracker" 2>/dev/null
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
  yq -r '.version // ""' "$tracker" 2>/dev/null
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
