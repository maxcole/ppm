#!/usr/bin/env bash
# Installing and removing packages: the install/remove commands, the hook lifecycle, and stow

# Shared stow ignore list. Layers of the same package name (e.g. user/git, pde/git)
# accumulate into one list so lower-priority layers skip files stowed by higher ones.
# install() resets it when moving on to a different package name.
PPM_IGNORE_ARGS=()

# Brew formulas and casks installed by the current run (newline-separated), for the trackers
PPM_NEW_BREW=""
PPM_NEW_CASK=""

# --- Commands ---

# Install one or more packages as requested by the user
install() {
  update_ppm_if_needed
  update_brew_if_needed
  expand_packages "install" "$@"
  # Reinstall only re-stows files: bypass pre_remove guards, and keep trackers and dependencies
  $reinstall && force=true keep_tracker=true remover "${EXPANDED_PACKAGES[@]}"

  collect_repos

  if ! $skip_deps; then
    resolve_deps "${EXPANDED_PACKAGES[@]}"
  else
    # Skip deps mode: just resolve the requested packages, no transitive deps
    RESOLVE_ORDER=()
    RESOLVE_DIRS=()
    local pkg matches repo_index repo_name pkg_dir
    for pkg in "${EXPANDED_PACKAGES[@]}"; do
      matches=$(find_package_dirs "$pkg") || { echo "Error: package '$pkg' not found"; exit 1; }
      while IFS=$'\t' read -r repo_index repo_name pkg_dir; do
        RESOLVE_ORDER+=("$repo_name/${pkg##*/}")
        RESOLVE_DIRS+=("$pkg_dir")
      done <<< "$matches"
    done
  fi

  local i unsupported=""
  for i in "${!RESOLVE_DIRS[@]}"; do
    if ! meta_supported "${RESOLVE_DIRS[$i]}"; then
      unsupported="$unsupported"$'\n'"  ${RESOLVE_ORDER[$i]} (platforms: $(echo $(meta_platforms "${RESOLVE_DIRS[$i]}")))"
    fi
  done
  if [[ -n "$unsupported" ]]; then
    echo "Error: not supported on $(platform):$unsupported"
    exit 1
  fi

  echo "Installing ${#RESOLVE_ORDER[@]} package(s):"
  for pkg in "${RESOLVE_ORDER[@]}"; do
    echo "  $pkg"
  done
  echo ""

  # Declared dependencies first, so hooks can rely on them
  if ! ${config:-false}; then
    _install_declared_deps || { flush_user_messages; exit 1; }
  fi

  # Install in topological order
  local idx=0 prev_name=""
  for qualified in "${RESOLVE_ORDER[@]}"; do
    local package_name="${qualified##*/}"

    # Layers of the same package name share one stow ignore list
    if [[ "$package_name" != "$prev_name" ]]; then
      PPM_IGNORE_ARGS=()
      prev_name="$package_name"
    fi

    install_single_package "${qualified%%/*}" "$package_name" "${RESOLVE_DIRS[$idx]}"
    idx=$((idx + 1))
  done

  ${config:-false} || _mise_install_declared
  flush_user_messages
}

# Remove one or more packages as requested by the user
remove() {
  expand_packages "remove" "$@"
  remover "${EXPANDED_PACKAGES[@]}"
  flush_user_messages
}

# --- Lifecycle ---

# Install a single resolved package: pre_install, stow, install_<os>, post_install, track
# Hooks are skipped with -c (config only)
# Arguments: repo_name package_name package_dir
install_single_package() {
  local repo_name="$1" pkg_name="$2" pkg_dir="$3"
  local hook="$pkg_dir/install.sh" run_hooks=true
  [[ -f "$hook" ]] && ! ${config:-false} || run_hooks=false

  PPM_CURRENT_PACKAGE="$repo_name/$pkg_name"
  echo "Install $repo_name/$pkg_name"
  debug "Package dir: $pkg_dir"

  if $run_hooks; then
    (
      source "$hook"
      if type pre_install &>/dev/null; then
        pre_install
      fi
    )
  fi

  stow_package "$pkg_dir"
  meta_cleanup_stale "$repo_name" "$pkg_name" "$pkg_dir" "$STOWED_FILES"

  if $run_hooks; then
    (
      source "$hook"
      local func_name="install_$(os)"
      if type "$func_name" &>/dev/null; then
        "$func_name"
      fi
      if type post_install &>/dev/null; then
        post_install
      fi
    )
  fi

  # Write tracker after all phases succeed. Record each declared formula/cask that ppm installed,
  # in this run or earlier for another package, so it is removed only when its last package goes.
  # Software the user installed themselves is never recorded.
  local manager name new="" new_brew="" new_cask="" installed_now
  for manager in brew cask; do
    new=""
    [[ "$manager" == "brew" ]] && installed_now="$PPM_NEW_BREW" || installed_now="$PPM_NEW_CASK"
    for name in $(meta_deps "$pkg_dir" "$manager"); do
      if grep -qxF -- "$name" <<< "$installed_now" || _dep_recorded_by_ppm "$manager" "$name"; then
        new="$new $name"
      fi
    done
    [[ "$manager" == "brew" ]] && new_brew="$new" || new_cask="$new"
  done
  meta_mark_installed "$repo_name" "$pkg_name" "$pkg_dir" "$STOWED_FILES" "$new_brew" "$new_cask"
}

# Remove packages by name; "pkg" removes every layer, "repo/pkg" only that one
# Arguments: package_spec [package_spec ...]
remover() {
  collect_repos
  local pkg pkg_name matches repo_index repo_name pkg_dir has_hook

  for pkg in "$@"; do
    pkg_name="${pkg##*/}"
    matches=$(find_package_dirs "$pkg") || continue

    # fd 3 keeps hooks that read stdin from consuming the match list
    while IFS=$'\t' read -r -u 3 repo_index repo_name pkg_dir; do
      PPM_CURRENT_PACKAGE="$repo_name/$pkg_name"
      echo "Remove $repo_name/$pkg_name"

      [[ -f "$pkg_dir/install.sh" ]] && has_hook=true || has_hook=false

      # Phase 1: pre_remove hook — a non-zero return aborts the removal unless -f
      if $has_hook; then
        if ! ( source "$pkg_dir/install.sh"; ! type pre_remove &>/dev/null || pre_remove ); then
          if ${force:-false}; then
            echo "Warning: pre_remove failed for $repo_name/$pkg_name; continuing (-f)"
          else
            echo "Aborted: $repo_name/$pkg_name not removed (use -f to force)"
            exit 1
          fi
        fi
      fi

      # Phase 2: unstow
      unstow_package "$pkg_dir"

      # Phase 3: OS-specific remove + post_remove
      if $has_hook; then
        (
          source "$pkg_dir/install.sh"
          func_name="remove_$(os)"
          type $func_name &>/dev/null && $func_name || true
          type post_remove &>/dev/null && post_remove || true
        )
      fi

      # Phase 4: dependencies ppm installed that nothing else needs, then the tracker
      # (skipped by reinstall, which installs the package again right away)
      if ! ${keep_tracker:-false}; then
        _remove_installed_deps "$repo_name" "$pkg_name" "$pkg_dir"
        meta_mark_removed "$repo_name" "$pkg_name"
      fi
    done 3<<< "$matches"
  done
}

# --- Declared dependencies (package.yml brew, cask, system) ---

# Install what the resolved packages declare, one batch per manager, only what is missing.
# System packages first (one sudo prompt), then brew formulas and casks (Homebrew owner only).
# Sets PPM_NEW_BREW / PPM_NEW_CASK to what this run installed.
_install_declared_deps() {
  local dir names system_all="" brew_all="" cask_all="" missing i
  PPM_NEW_BREW=""
  PPM_NEW_CASK=""

  for i in "${!RESOLVE_DIRS[@]}"; do
    dir="${RESOLVE_DIRS[$i]}"
    if ! names=$(meta_deps "$dir" system); then
      ppm_fail "${RESOLVE_ORDER[$i]} declares system packages, but none for $(platform)"
      return 1
    fi
    system_all=$(_list_add "$system_all" $names)
    brew_all=$(_list_add "$brew_all" $(meta_deps "$dir" brew))
    cask_all=$(_list_add "$cask_all" $(meta_deps "$dir" cask))
  done
  debug "Declared system: $(echo $system_all) | brew: $(echo $brew_all) | cask: $(echo $cask_all)"

  missing=$(system_pkg_missing $system_all)
  if [[ -n "$missing" ]]; then
    echo "System packages to install: $(echo $missing)"
    system_pkg_install $missing || { ppm_fail "Failed to install system packages: $(echo $missing)"; return 1; }
  fi

  missing=$(brew_missing $brew_all)
  if [[ -n "$missing" ]]; then
    brew_require_owner "brew install $(echo $missing)" || return 1
    echo "Brew formulas to install: $(echo $missing)"
    brew install --yes $missing </dev/null || { ppm_fail "brew install failed: $(echo $missing)"; return 1; }
    PPM_NEW_BREW="$missing"
  fi

  missing=$(cask_missing $cask_all)
  if [[ -n "$missing" ]]; then
    brew_require_owner "brew install --cask $(echo $missing)" || return 1
    echo "Casks to install: $(echo $missing)"
    brew install --yes --cask $missing </dev/null || { ppm_fail "brew install --cask failed: $(echo $missing)"; return 1; }
    PPM_NEW_CASK="$missing"
  fi
}

# Install the mise tools named in the resolved packages' mise config (.config/mise/**/*.toml),
# in one call from $HOME so a project's config in the current directory doesn't interfere
_mise_install_declared() {
  local dir file tools=""
  for dir in "${RESOLVE_DIRS[@]}"; do
    while IFS= read -r file; do
      [[ -n "$file" ]] || continue
      tools=$(_list_add "$tools" $(yq -p toml -oy -r '.tools // {} | keys | .[]' "$file" 2>/dev/null))
    done < <(find "$dir/home/.config/mise" ${PPM_GROUP_ID:+"$dir/$PPM_GROUP_ID/.config/mise"} -name '*.toml' 2>/dev/null)
  done
  [[ -n "$tools" ]] || return 0

  if ! command -v mise >/dev/null 2>&1; then
    ppm_fail "mise is not installed; these tools were not installed: $(echo $tools)"
    return 0
  fi
  echo "mise install $(echo $tools)"
  (cd "$HOME" && mise install $tools </dev/null) || ppm_fail "mise install failed for: $(echo $tools)"
}

# Uninstall the brew formulas and casks ppm installed for a package, unless another installed
# package also installed or declares them. System packages are never removed.
_remove_installed_deps() {
  local repo="$1" pkg="$2" pkg_dir="$3" manager name uninstall system_names
  PPM_CURRENT_PACKAGE="$repo/$pkg"

  system_names=$(meta_deps "$pkg_dir" system 2>/dev/null) || system_names=""
  [[ -z "$system_names" ]] || user_message "System packages were left installed: $(echo $system_names)"

  for manager in brew cask; do
    uninstall=""
    for name in $(meta_installed_deps "$repo" "$pkg" "$manager"); do
      if _dep_needed_elsewhere "$manager" "$name" "$repo/$pkg"; then
        debug "Keeping $name: another installed package needs it"
      else
        uninstall="$uninstall $name"
      fi
    done
    [[ -n "$uninstall" ]] || continue

    if ! brew_is_owner; then
      user_message "Not removed (Homebrew is owned by $(brew_owner 2>/dev/null || echo nobody)):$uninstall"
      continue
    fi
    echo "Uninstalling $manager:$uninstall"
    if [[ "$manager" == "cask" ]]; then
      brew uninstall --cask $uninstall </dev/null || user_message "Could not uninstall cask:$uninstall"
    else
      brew uninstall $uninstall </dev/null || user_message "Could not uninstall:$uninstall (another formula may depend on it)"
    fi
  done
}

# True when any tracker records <name> as installed by ppm
# Usage: _dep_recorded_by_ppm <brew|cask> <name>
_dep_recorded_by_ppm() {
  local manager="$1" name="$2" tracker qualified
  for tracker in "$PPM_INSTALLED_DIR"/*/*.yml; do
    [[ -f "$tracker" ]] || continue
    qualified="${tracker#$PPM_INSTALLED_DIR/}"
    qualified="${qualified%.yml}"
    grep -qxF -- "$name" <<< "$(meta_installed_deps "${qualified%%/*}" "${qualified#*/}" "$manager")" && return 0
  done
  return 1
}

# True when another installed package recorded or declares <name> for <manager>
# Usage: _dep_needed_elsewhere <brew|cask> <name> <repo/pkg to ignore>
_dep_needed_elsewhere() {
  local manager="$1" name="$2" self="$3" tracker qualified repo pkg dir
  for tracker in "$PPM_INSTALLED_DIR"/*/*.yml; do
    [[ -f "$tracker" ]] || continue
    qualified="${tracker#$PPM_INSTALLED_DIR/}"
    qualified="${qualified%.yml}"
    [[ "$qualified" == "$self" ]] && continue
    repo="${qualified%%/*}"
    pkg="${qualified#*/}"

    grep -qxF -- "$name" <<< "$(meta_installed_deps "$repo" "$pkg" "$manager")" && return 0
    dir="$PPM_DATA_HOME/$repo/packages/$pkg"
    [[ -d "$dir" ]] && grep -qxF -- "$name" <<< "$(meta_deps "$dir" "$manager" 2>/dev/null)" && return 0
  done
  return 1
}

# Remove stale files left over from a previous install
# Compares old tracked files against new file list,
# only removes symlinks that point into the given package dir
# Usage: meta_cleanup_stale <repo_name> <package_name> <package_dir> <new_files>
meta_cleanup_stale() {
  local repo_name="$1" pkg_name="$2" pkg_dir="$3" new_files="$4"

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

# --- Stow ---

# Stow a package's home/ and $PPM_GROUP_ID subdirs into $HOME
# Files already in PPM_IGNORE_ARGS (owned by a higher-priority layer) are skipped
# Sets STOWED_FILES to the newline-separated files this layer stows
# (a global, not stdout: stow_subdir must update PPM_IGNORE_ARGS in this shell)
stow_package() {
  local pkg_dir="$1" subdir file
  STOWED_FILES=""

  for subdir in home ${PPM_GROUP_ID:-}; do
    [[ -d "$pkg_dir/$subdir" ]] || continue

    while IFS= read -r file; do
      if [[ -n "$file" ]] && ! is_stow_ignored "$file"; then
        STOWED_FILES="${STOWED_FILES:+${STOWED_FILES}$'\n'}${file}"
      fi
    done < <(package_links "$pkg_dir/$subdir")

    stow_subdir "$pkg_dir" "$subdir"
  done
}

# Unstow a package's home/ and $PPM_GROUP_ID subdirs from $HOME
unstow_package() {
  local pkg_dir="$1" subdir

  for subdir in home ${PPM_GROUP_ID:-}; do
    [[ -d "$pkg_dir/$subdir" ]] && stow -D -d "$pkg_dir" -t "$HOME" "$subdir"
  done
  return 0
}

# Build the stow --ignore argument for a file path relative to the stow dir
_stow_ignore_arg() {
  local escaped="${1//./\\.}"
  echo "--ignore=^${escaped}\$"
}

# Check whether a file path is already in PPM_IGNORE_ARGS
is_stow_ignored() {
  local escaped="${1//./\\.}" arg
  for arg in ${PPM_IGNORE_ARGS[@]+"${PPM_IGNORE_ARGS[@]}"}; do
    [[ "$arg" == "--ignore=^${escaped}\$" ]] && return 0
  done
  return 1
}

# Stow a package subdirectory and add its files to PPM_IGNORE_ARGS
stow_subdir() {
  local pkg_dir="$1" subdir="$2"
  local full_path="$pkg_dir/$subdir"

  [[ -d "$full_path" ]] || return 0
  debug "Stowing $subdir from $pkg_dir"

  # If force mode, remove conflicting files first
  $force && force_remove_conflicts "$full_path"

  stow --no-folding ${PPM_IGNORE_ARGS[@]+"${PPM_IGNORE_ARGS[@]}"} -d "$pkg_dir" -t "$HOME" "$subdir"

  while IFS= read -r file; do
    if [[ -n "$file" ]] && ! is_stow_ignored "$file"; then
      PPM_IGNORE_ARGS+=("$(_stow_ignore_arg "$file")")
    fi
  done < <(package_links "$full_path")
}

# List files in a directory, relative to it
package_links() {
  local path="$1"
  find "$path" -type f | while read -r file; do
    echo "${file#$path/}"
  done
}

# Remove files from $HOME that would conflict with stow
# Files in PPM_IGNORE_ARGS (stowed by a previous subdir or higher-priority layer) are kept
force_remove_conflicts() {
  local full_path="$1"

  while IFS= read -r file; do
    [[ -z "$file" ]] && continue

    # Remove the file from $HOME if it exists and isn't ignored
    if ! is_stow_ignored "$file" && [[ -e "$HOME/$file" || -L "$HOME/$file" ]]; then
      rm -f "$HOME/$file"
    fi
  done < <(package_links "$full_path")
}
