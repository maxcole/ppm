#!/usr/bin/env bash
# Packages: discovery, dependency resolution, package.yml metadata, install trackers,
# and the list/show/path/deps commands
# Compatible with bash 3.2 (no associative arrays)

# --- Discovery ---

# Collect "repo/pkg" names into PACKAGES, optionally filtered to specific repos
# Usage: collect_packages [repo1 repo2 ...]
collect_packages() {
  local filter_repos
  filter_repos=("$@")
  PACKAGES=()

  # If no filter provided, get all repo names from sources
  if [[ ${#filter_repos[@]} -eq 0 ]]; then
    collect_repos
    filter_repos=(${REPO_NAMES[@]+"${REPO_NAMES[@]}"})
  fi

  for repo_name in ${filter_repos[@]+"${filter_repos[@]}"}; do
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
      local supported=() p
      for p in "${PACKAGES[@]}"; do
        if meta_supported "$PPM_DATA_HOME/${p%%/*}/packages/${p#*/}"; then
          supported+=("$p")
        else
          echo "Skipping $p: not supported on $(platform)"
        fi
      done
      [[ ${#supported[@]} -gt 0 ]] || { echo "Error: No packages in repo '$arg' support $(platform)"; exit 1; }
      PACKAGES=("${supported[@]}")
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

    local pkg_dir="$PPM_DATA_HOME/$repo_name/packages/$package_name"
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

# --- Dependency graph ---

# Arrays populated by resolve_deps:
#   RESOLVE_ORDER  — indexed array of "repo/pkg" in install order (deps first)
#   RESOLVE_DIRS   — parallel array of package directories
RESOLVE_ORDER=()
RESOLVE_DIRS=()

# Internal state for resolution
_RESOLVED=""    # newline-separated list of resolved "repo/pkg"
_RESOLVING=""   # newline-separated list of packages currently being resolved (cycle detection)

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
  local matches repo_index repo_name pkg_dir

  matches=$(find_package_dirs "$pkg" "$min_index") || {
    echo "Error: package '$pkg' not found" >&2
    exit 1
  }

  # Collect the layers (one per repo) that are not yet resolved
  local layer_names=() layer_dirs=() layer_indexes=()
  while IFS=$'\t' read -r repo_index repo_name pkg_dir; do
    [[ -z "$repo_index" ]] && continue
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
    layer_dirs+=("$pkg_dir")
    layer_indexes+=("$repo_index")
  done <<< "$matches"

  [[ ${#layer_names[@]} -eq 0 ]] && return 0

  # Resolve dependencies of every layer first (depth-first)
  # Dependencies can only come from the same repo or lower-priority repos
  # A dependency on a sibling layer (e.g. user/git depends on pde/git) is satisfied by the group itself
  local i dep deps
  for i in "${!layer_names[@]}"; do
    deps=$(meta_depends "${layer_dirs[$i]}")
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

# --- package.yml ---

# Read the depends list from package.yml
# Returns one dependency per line (suitable for while-read loops)
# Usage: meta_depends <package_dir>
meta_depends() {
  local meta="$1/package.yml"
  [[ -f "$meta" ]] || return 0
  yq -r '.depends[]? // ""' "$meta" 2>/dev/null
}

# Read the version from package.yml
# Usage: meta_version <package_dir>
meta_version() {
  local meta="$1/package.yml"
  [[ -f "$meta" ]] || return 0
  yq -r '.version // ""' "$meta" 2>/dev/null
}

# Platforms a package supports (macos, linux, debian, fedora); nothing means every platform
# Usage: meta_platforms <package_dir>
meta_platforms() {
  local meta="$1/package.yml"
  [[ -f "$meta" ]] || return 0
  yq -r '.platforms[]? // ""' "$meta" 2>/dev/null
}

# True when the package supports this machine; "linux" covers every Linux distro
# Usage: meta_supported <package_dir>
meta_supported() {
  local platforms current p
  platforms=$(meta_platforms "$1")
  [[ -z "$platforms" ]] && return 0
  current=$(platform)
  for p in $platforms; do
    [[ "$p" == "$current" ]] && return 0
    [[ "$p" == "linux" && "$current" != "macos" ]] && return 0
  done
  return 1
}

# Dependencies a package declares for one manager (brew, cask or system), resolved for this platform.
# A list applies on every platform. A map is keyed by platform: the exact platform first, then
# "linux" on any Linux distro. Returns 1 for a system map that names other Linux distros but
# neither this one nor "linux", so callers can fail instead of skipping silently.
# Usage: meta_deps <package_dir> <brew|cask|system>
meta_deps() {
  local meta="$1/package.yml" key="$2" type current
  [[ -f "$meta" ]] || return 0

  type=$(K="$key" yq -r '.[strenv(K)] | type' "$meta" 2>/dev/null)
  case "$type" in
    '!!seq')
      K="$key" yq -r '.[strenv(K)][]' "$meta" 2>/dev/null
      ;;
    '!!map')
      current=$(platform)
      if K="$key" P="$current" yq -e '.[strenv(K)] | has(strenv(P))' "$meta" >/dev/null 2>&1; then
        K="$key" P="$current" yq -r '.[strenv(K)][strenv(P)][]?' "$meta" 2>/dev/null
      elif [[ "$current" != "macos" ]] && K="$key" yq -e '.[strenv(K)] | has("linux")' "$meta" >/dev/null 2>&1; then
        K="$key" yq -r '.[strenv(K)].linux[]?' "$meta" 2>/dev/null
      elif [[ "$key" == "system" && "$current" != "macos" ]] &&
           K="$key" yq -e '.[strenv(K)] | keys | map(select(. != "macos")) | length > 0' "$meta" >/dev/null 2>&1; then
        return 1
      fi
      ;;
  esac
  return 0
}

# Add items to a newline-separated list, skipping empty items and duplicates (keeps first-seen order)
# Usage: list=$(_list_add "$list" item...)
_list_add() {
  local list="$1" item
  shift
  for item in "$@"; do
    [[ -n "$item" ]] || continue
    grep -qxF -- "$item" <<< "$list" || list="${list:+$list$'\n'}$item"
  done
  printf '%s' "$list"
}

# --- Install trackers ($PPM_INSTALLED_DIR/<repo>/<pkg>.yml) ---

# Path to a package's tracker file
_tracker_path() {
  echo "$PPM_INSTALLED_DIR/$1/$2.yml"
}

# Record a package as installed with its stowed files and the brew formulas and casks ppm
# installed for it. Dependencies recorded by an earlier install are kept, so a later install that
# finds them already present doesn't lose track of who installed them.
# Usage: meta_mark_installed <repo_name> <package_name> <package_dir> <files> [brew_names] [cask_names]
# files are newline-separated; brew/cask names are whitespace-separated
meta_mark_installed() {
  local repo_name="$1" pkg_name="$2" pkg_dir="$3" stowed_files="$4" new_brew="${5:-}" new_cask="${6:-}"
  local tracker
  tracker=$(_tracker_path "$repo_name" "$pkg_name")
  local version
  version=$(meta_version "$pkg_dir")
  [[ -z "$version" ]] && version="unknown"

  local timestamp
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  # Read before the tracker is rewritten
  local brew cask
  brew=$(_list_add "$(meta_installed_deps "$repo_name" "$pkg_name" brew)" $new_brew)
  cask=$(_list_add "$(meta_installed_deps "$repo_name" "$pkg_name" cask)" $new_cask)

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
    if [[ -n "$brew$cask" ]]; then
      echo "installed_deps:"
      [[ -z "$brew" ]] || { echo "  brew:"; printf '    - %s\n' $brew; }
      [[ -z "$cask" ]] || { echo "  cask:"; printf '    - %s\n' $cask; }
    fi
  } > "$tracker"
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

# Read previously stowed files from tracker
# Usage: meta_installed_files <repo_name> <package_name>
meta_installed_files() {
  local tracker
  tracker=$(_tracker_path "$1" "$2")
  [[ -f "$tracker" ]] || return 0
  yq -r '.files[]? // ""' "$tracker" 2>/dev/null
}

# Brew formulas or casks that ppm installed for a package, one per line
# Usage: meta_installed_deps <repo_name> <package_name> <brew|cask>
meta_installed_deps() {
  local tracker
  tracker=$(_tracker_path "$1" "$2")
  [[ -f "$tracker" ]] || return 0
  M="$3" yq -r '.installed_deps[strenv(M)][]?' "$tracker" 2>/dev/null
}

# Add a file to a package's install tracker (creating the tracker if needed)
_tracker_add_file() {
  local repo="$1" pkg="$2" pkg_dir="$3" rel="$4"
  local tracker
  tracker=$(_tracker_path "$repo" "$pkg")
  if [[ -f "$tracker" ]]; then
    F="$rel" yq -i '.files = ((.files // []) + [strenv(F)] | unique)' "$tracker"
  else
    meta_mark_installed "$repo" "$pkg" "$pkg_dir" "$(package_links "$pkg_dir/home")"
  fi
}

# Remove a file from a package's install tracker
_tracker_remove_file() {
  local tracker
  tracker=$(_tracker_path "$1" "$2")
  [[ -f "$tracker" ]] || return 0
  F="$3" yq -i 'del(.files[] | select(. == strenv(F)))' "$tracker"
}

# --- Commands ---

# List the packages found in the cached repositories
# Optionally filter by a substring pattern
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
      pkg_name="${pkg_name#$PPM_INSTALLED_DIR/}"
      local version
      version=$(yq -r '.version // "?"' "$tracker" 2>/dev/null)
      local line="$pkg_name  $version"
      if [[ -z "$filter" ]] || [[ "$line" == *"$filter"* ]]; then
        echo "$line"
      fi
    done
    return
  fi

  collect_packages
  for pkg in ${PACKAGES[@]+"${PACKAGES[@]}"}; do
    if [[ -z "$filter" ]] || [[ "$pkg" == *"$filter"* ]]; then
      echo "$pkg"
    fi
  done
}

# Show package information: version, dependencies, install status and home/ tree
show() {
  if [[ $# -eq 0 ]]; then
    echo "Error: show requires a package name"
    echo "Usage: ppm show [repo/]package"
    exit 1
  fi

  collect_repos

  local pkg="$1" matches repo_index repo_name package_dir
  local package_name="${pkg##*/}"
  matches=$(find_package_dirs "$pkg") || { echo "Error: package '$pkg' not found"; exit 1; }

  while IFS=$'\t' read -r -u 3 repo_index repo_name package_dir; do
    echo "package: $repo_name/$package_name"
    echo ""

    local version
    version=$(meta_version "$package_dir")
    if [[ -n "$version" ]]; then
      echo "Version: $version"
    fi

    local deps
    deps=$(meta_depends "$package_dir")
    if [[ -n "$deps" ]]; then
      echo "Dependencies:"
      for dep in $deps; do
        echo "  - $dep"
      done
      echo ""
    fi

    local platforms_list manager names label shown=false
    platforms_list=$(meta_platforms "$package_dir")
    if [[ -n "$platforms_list" ]]; then
      echo "Platforms: $(echo $platforms_list)"
      shown=true
    fi
    for manager in brew cask system; do
      case "$manager" in
        brew) label="Brew" ;;
        cask) label="Cask" ;;
        system) label="System ($(platform))" ;;
      esac
      names=$(meta_deps "$package_dir" "$manager") || names="none declared for $(platform)"
      if [[ -n "$names" ]]; then
        echo "$label: $(echo $names)"
        shown=true
      fi
    done
    ! $shown || echo ""

    if meta_is_installed "$repo_name" "$package_name"; then
      local inst_version
      inst_version=$(meta_installed_version "$repo_name" "$package_name")
      echo "Status: installed (v${inst_version})"

      for manager in brew cask; do
        names=$(meta_installed_deps "$repo_name" "$package_name" "$manager")
        [[ -z "$names" ]] || echo "Installed by ppm ($manager): $(echo $names)"
      done

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
    echo ""

    if [[ -d "$package_dir/home" ]]; then
      echo "home/"
      if command -v tree &>/dev/null; then
        tree -a --noreport "$package_dir/home" | tail -n +2
      else
        find "$package_dir/home" -type f | sed "s|$package_dir/home/|  |"
      fi
      echo ""
    fi
  done 3<<< "$matches"
}

# Output the path to a package directory (the highest-priority layer)
path() {
  local verbose=false
  [[ "${1:-}" == "-v" ]] && { verbose=true; shift; }

  if [[ $# -eq 0 ]]; then
    echo "Error: path requires a package name"
    echo "Usage: ppm path [-v] [repo/]package"
    exit 1
  fi

  collect_repos

  local pkg="$1" matches repo_index repo_name package_dir
  matches=$(find_package_dirs "$pkg") || { echo "Error: package '$pkg' not found" >&2; exit 1; }

  if $verbose && [[ "$matches" == *$'\n'* ]]; then
    echo "Warning: package '$pkg' found in multiple repos, using first match:" >&2
    while IFS=$'\t' read -r repo_index repo_name package_dir; do
      echo "  $repo_name/${pkg##*/}" >&2
    done <<< "$matches"
  fi

  matches="${matches%%$'\n'*}"
  echo "${matches##*$'\t'}"
}

# Show resolved dependency tree without installing
deps() {
  if [[ $# -eq 0 ]]; then
    echo "Usage: ppm deps <package> [package...]"
    exit 1
  fi

  collect_repos
  resolve_deps "$@"

  echo "Install order (${#RESOLVE_ORDER[@]} packages):"
  for pkg in "${RESOLVE_ORDER[@]}"; do
    echo "  $pkg"
  done
}
