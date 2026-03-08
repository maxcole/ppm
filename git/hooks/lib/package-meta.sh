#!/usr/bin/env bash
# Library for reading/writing package.yml metadata
# Sourced by git hooks and ppm internals

# Read a value from package.yml
# Usage: meta_read <package_dir> <key>
# Returns empty string if file or key doesn't exist
meta_read() {
  local pkg_dir="$1" key="$2"
  local meta_file="$pkg_dir/package.yml"
  [[ -f "$meta_file" ]] || return 0
  grep "^${key}:" "$meta_file" | sed "s/^${key}: *//"
}

# Write a key-value pair to package.yml
# Creates the file if it doesn't exist
# Usage: meta_write <package_dir> <key> <value>
meta_write() {
  local pkg_dir="$1" key="$2" value="$3"
  local meta_file="$pkg_dir/package.yml"

  if [[ ! -f "$meta_file" ]]; then
    echo "${key}: ${value}" > "$meta_file"
  elif grep -q "^${key}:" "$meta_file"; then
    if [[ "$(uname)" == "Darwin" ]]; then
      sed -i '' "s/^${key}: .*/${key}: ${value}/" "$meta_file"
    else
      sed -i "s/^${key}: .*/${key}: ${value}/" "$meta_file"
    fi
  else
    echo "${key}: ${value}" >> "$meta_file"
  fi
}

# Bump the patch version in package.yml
# Returns the new version string
# Usage: meta_bump_patch <package_dir>
meta_bump_patch() {
  local pkg_dir="$1"
  local version
  version=$(meta_read "$pkg_dir" "version")

  if [[ -z "$version" ]]; then
    meta_write "$pkg_dir" "version" "0.1.0"
    echo "0.1.0"
    return
  fi

  IFS='.' read -r major minor patch <<< "$version"
  local new_version="${major}.${minor}.$((patch + 1))"
  meta_write "$pkg_dir" "version" "$new_version"
  echo "$new_version"
}

# Extract dependencies from install.sh by parsing the dependencies() function
# Usage: meta_extract_depends <package_dir>
meta_extract_depends() {
  local pkg_dir="$1"
  local install_file="$pkg_dir/install.sh"
  [[ -f "$install_file" ]] || return 0

  # Source in subshell and call dependencies() if it exists
  (
    source "$install_file" 2>/dev/null
    if type dependencies &>/dev/null; then
      dependencies
    fi
  )
}

# Detect supported OS from install.sh function names
# Returns YAML array string like "[macos, linux]"
# Usage: meta_detect_os <package_dir>
meta_detect_os() {
  local pkg_dir="$1"
  local install_file="$pkg_dir/install.sh"
  local has_macos=false has_linux=false

  if [[ ! -f "$install_file" ]]; then
    # No install.sh — home-only package, assume both
    echo "[macos, linux]"
    return
  fi

  grep -q 'install_macos' "$install_file" && has_macos=true
  grep -q 'install_linux' "$install_file" && has_linux=true

  # If neither OS-specific function found, check for generic hooks only
  if ! $has_macos && ! $has_linux; then
    # Has install.sh but no OS-specific functions — assume both
    echo "[macos, linux]"
  elif $has_macos && $has_linux; then
    echo "[macos, linux]"
  elif $has_macos; then
    echo "[macos]"
  else
    echo "[linux]"
  fi
}

# Format depends list as YAML array string
# Usage: meta_format_depends "mise ruby"  →  "[mise, ruby]"
meta_format_depends() {
  local deps="$1"
  [[ -z "$deps" ]] && return 0
  echo "[$(echo "$deps" | xargs | tr ' ' ', ')]"
}

# Bootstrap a package.yml from install.sh contents
# Usage: meta_bootstrap <package_dir>
meta_bootstrap() {
  local pkg_dir="$1"
  local meta_file="$pkg_dir/package.yml"

  [[ -f "$meta_file" ]] && return 0

  local deps os_list

  deps=$(meta_extract_depends "$pkg_dir")
  os_list=$(meta_detect_os "$pkg_dir")

  echo "version: 0.1.0" > "$meta_file"
  echo "os: ${os_list}" >> "$meta_file"

  if [[ -n "$deps" ]]; then
    echo "depends: $(meta_format_depends "$deps")" >> "$meta_file"
  fi
}
