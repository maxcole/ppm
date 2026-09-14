#!/usr/bin/env bash
# Dependency graph resolution for ppm
# Compatible with bash 3.2 (no associative arrays)

# Arrays populated by resolve_deps:
#   RESOLVE_ORDER  — indexed array of "repo/pkg" in install order (deps first)
#   RESOLVE_DIRS   — parallel array of package directories
RESOLVE_ORDER=()
RESOLVE_DIRS=()

# Internal state for resolution
_RESOLVED=""    # newline-separated list of resolved "repo/pkg"
_RESOLVING=""   # newline-separated list of packages currently being resolved (cycle detection)

# Find all package directories for a given package specifier
# "repo/pkg" matches only that repo; "pkg" matches every repo containing it, in source order.
# Multiple matches are layers: higher-priority layers stow first and lower layers skip their files.
# Outputs one "repo_index<TAB>repo_name<TAB>pkg_dir" line per match; returns 1 if none
# Optional second arg restricts search to repos at index >= min_index
# (enforces layered dependency rule: repos can only depend on same or lower-priority repos)
# Usage: find_package_dirs <package_spec> [min_index]
find_package_dirs() {
  local pkg="$1"
  local min_index="${2:-0}"
  local package_repo="" package_name="" found=false

  if [[ "$pkg" == */* ]]; then
    package_repo="${pkg%%/*}"
    package_name="${pkg##*/}"
  else
    package_name="$pkg"
  fi

  for i in "${!REPO_URLS[@]}"; do
    [[ $i -lt $min_index ]] && continue
    local repo_name="${REPO_NAMES[$i]}"
    [[ -n "$package_repo" && "$repo_name" != "$package_repo" ]] && continue

    local pkg_dir="$PPM_DATA_HOME/$repo_name/$PPM_ASSET_DIR/$package_name"
    if [[ -d "$pkg_dir" ]]; then
      printf '%s\t%s\t%s\n' "$i" "$repo_name" "$pkg_dir"
      found=true
    fi
  done

  $found
}

# Find the first (highest-priority) package directory for a given package specifier
# Outputs "repo_index<TAB>repo_name<TAB>pkg_dir" on success
# Usage: find_package_dir <package_spec> [min_index]
find_package_dir() {
  local matches
  matches=$(find_package_dirs "$@") || return 1
  echo "${matches%%$'\n'*}"
}

# Resolve full dependency tree for a list of packages
# Populates RESOLVE_ORDER and RESOLVE_DIRS
# Usage: resolve_deps pkg1 [pkg2 ...]
resolve_deps() {
  RESOLVE_ORDER=()
  RESOLVE_DIRS=()
  _RESOLVED=""
  _RESOLVING=""

  for pkg in "$@"; do
    _resolve_one "$pkg"
  done
}

_resolve_one() {
  local pkg="$1"
  local min_index="${2:-0}"
  local pkg_name="${pkg##*/}"
  local matches line

  matches=$(find_package_dirs "$pkg" "$min_index") || {
    echo "Error: ${PPM_ASSET_LABEL} '$pkg' not found" >&2
    exit 1
  }

  # Collect the layers (one per repo) that are not yet resolved
  local layer_names=() layer_dirs=() layer_indexes=()
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    local repo_index="${line%%	*}"
    local rest="${line#*	}"
    local repo_name="${rest%%	*}"
    local qualified_name="${repo_name}/${pkg_name}"

    # Already resolved — skip
    if echo "$_RESOLVED" | grep -qxF "$qualified_name"; then
      continue
    fi

    # Cycle detection
    if echo "$_RESOLVING" | grep -qxF "$qualified_name"; then
      echo "Error: Circular dependency detected: $qualified_name" >&2
      exit 1
    fi
    _RESOLVING="${_RESOLVING}${qualified_name}"$'\n'

    layer_names+=("$qualified_name")
    layer_dirs+=("${rest#*	}")
    layer_indexes+=("$repo_index")
  done <<< "$matches"

  [[ ${#layer_names[@]} -eq 0 ]] && return 0

  # Resolve dependencies of every layer first (depth-first)
  # Dependencies can only come from the same repo or lower-priority repos
  # A dependency on a sibling layer (e.g. user/git depends on pde/git) is satisfied by the group itself
  local i dep deps
  for i in "${!layer_names[@]}"; do
    deps=$(resolve_package_deps "${layer_dirs[$i]}")
    for dep in $deps; do
      if [[ "$dep" == "$pkg_name" ]] || printf '%s\n' "${layer_names[@]}" | grep -qxF "$dep"; then
        continue
      fi
      _resolve_one "$dep" "${layer_indexes[$i]}"
    done
  done

  # Mark as resolved — layers are appended consecutively in source order
  # so install() stows them against one shared ignore list
  for i in "${!layer_names[@]}"; do
    _RESOLVED="${_RESOLVED}${layer_names[$i]}"$'\n'
    RESOLVE_ORDER+=("${layer_names[$i]}")
    RESOLVE_DIRS+=("${layer_dirs[$i]}")
    debug "Resolved: ${layer_names[$i]} -> ${layer_dirs[$i]}"
  done
}
