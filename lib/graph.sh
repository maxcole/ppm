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

# Find the package directory for a given package specifier
# Handles both "repo/pkg" and "pkg" (search all repos in order)
# Outputs "repo_index<TAB>repo_name<TAB>pkg_dir" on success
# Optional second arg restricts search to repos at index >= min_index
# (enforces layered dependency rule: repos can only depend on same or lower-priority repos)
# Usage: find_package_dir <package_spec> [min_index]
find_package_dir() {
  local pkg="$1"
  local min_index="${2:-0}"
  local package_repo="" package_name=""

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
      return 0
    fi
  done

  return 1
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
  local found repo_index repo_name pkg_dir

  found=$(find_package_dir "$pkg" "$min_index") || {
    echo "Error: ${PPM_ASSET_LABEL} '$pkg' not found" >&2
    exit 1
  }
  repo_index="${found%%	*}"
  local rest="${found#*	}"
  repo_name="${rest%%	*}"
  pkg_dir="${rest#*	}"
  local qualified_name="${repo_name}/${pkg##*/}"

  # Already resolved — skip
  if echo "$_RESOLVED" | grep -qxF "$qualified_name"; then
    return 0
  fi

  # Cycle detection
  if echo "$_RESOLVING" | grep -qxF "$qualified_name"; then
    echo "Error: Circular dependency detected: $qualified_name" >&2
    exit 1
  fi
  _RESOLVING="${_RESOLVING}${qualified_name}"$'\n'

  # Resolve dependencies first (depth-first)
  # Dependencies can only come from the same repo or lower-priority repos
  local deps
  deps=$(resolve_package_deps "$pkg_dir")
  if [[ -n "$deps" ]]; then
    for dep in $deps; do
      _resolve_one "$dep" "$repo_index"
    done
  fi

  # Mark as resolved
  _RESOLVED="${_RESOLVED}${qualified_name}"$'\n'
  RESOLVE_ORDER+=("$qualified_name")
  RESOLVE_DIRS+=("$pkg_dir")

  debug "Resolved: $qualified_name -> $pkg_dir"
}
