#!/usr/bin/env bash
# Package metadata functions — reads package.yml via yq

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
