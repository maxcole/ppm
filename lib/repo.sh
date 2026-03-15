#!/usr/bin/env bash
# Repository management functions for ppm

collect_repos() {
  REPO_URLS=()
  REPO_NAMES=()

  # Read file into array, skipping empty lines and comments
  # Supports two-column format: URL alias (alias is optional, defaults to basename)
  while IFS= read -r line || [ -n "$line" ]; do
    # Skip empty lines and comments
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue

    # Split on whitespace: first field is URL, second (optional) is alias
    local url name
    read -r url name <<< "$line"
    [[ -z "$name" ]] && name="$(basename "$url" .git)"

    REPO_URLS+=("$url")
    REPO_NAMES+=("$name")
    debug "Source: $url -> $name"
  done < "$PPM_SOURCES_FILE"
}

# Check if argument is a known repo name (exists in PPM_DATA_HOME)
is_repo_name() {
  local name="$1"
  [[ -d "$PPM_DATA_HOME/$name/packages" ]]
}

# Collect packages, optionally filtered to specific repos
# Usage: collect_packages [repo1 repo2 ...]
# If no args, collects from all repos
collect_packages() {
  local filter_repos
  filter_repos=("$@")
  PACKAGES=()

  # If no filter provided, get all repo names from sources
  if [[ ${#filter_repos[@]} -eq 0 ]]; then
    collect_repos
    filter_repos=("${REPO_NAMES[@]}")
  fi

  for repo_name in "${filter_repos[@]}"; do
    local repo_path="$PPM_DATA_HOME/$repo_name/packages"
    [[ -d "$repo_path" ]] || continue

    while IFS= read -r dir; do
      PACKAGES+=("$repo_name/$(basename "$dir")")
    done < <(ls -d "$repo_path"/*/ 2>/dev/null)
  done
}

# Expand repo-trailing-slash arguments into individual packages
# Sets EXPANDED_PACKAGES array in caller's scope
expand_packages() {
  local verb="$1"; shift
  EXPANDED_PACKAGES=()
  for arg in "$@"; do
    if [[ "$arg" == */ ]] && is_repo_name "${arg%/}"; then
      arg="${arg%/}"
      collect_packages "$arg"
      [[ ${#PACKAGES[@]} -eq 0 ]] && { echo "Error: No packages found in repo '$arg'"; exit 1; }
      if ! $force; then
        echo "About to $verb all packages (${#PACKAGES[@]}) from $arg:"
        printf '  %s\n' "${PACKAGES[@]}"
        read -p "Continue? [y/N] " confirm
        [[ "$confirm" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }
      fi
      EXPANDED_PACKAGES+=("${PACKAGES[@]}")
    else
      EXPANDED_PACKAGES+=("$arg")
    fi
  done
}
