#!/usr/bin/env bash
# Installing and removing packages: the install/remove commands, the hook lifecycle, and stow

# Shared stow ignore list. Layers of the same package name (e.g. user/git, pde/git)
# accumulate into one list so lower-priority layers skip files stowed by higher ones.
# install() resets it when moving on to a different package name.
PPM_IGNORE_ARGS=()

# --- Commands ---

# Install one or more packages as requested by the user
install() {
  update_ppm_if_needed
  update_brew_if_needed
  expand_packages "install" "$@"
  # Reinstall only re-stows files, so bypass pre_remove guards
  $reinstall && force=true remover "${EXPANDED_PACKAGES[@]}"

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

  echo "Installing ${#RESOLVE_ORDER[@]} package(s):"
  for pkg in "${RESOLVE_ORDER[@]}"; do
    echo "  $pkg"
  done
  echo ""

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

  # Write tracker after all phases succeed
  meta_mark_installed "$repo_name" "$pkg_name" "$pkg_dir" "$STOWED_FILES"
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

      # Phase 4: remove tracker
      meta_mark_removed "$repo_name" "$pkg_name"
    done 3<<< "$matches"
  done
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
