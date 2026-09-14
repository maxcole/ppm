#!/usr/bin/env bash
# Stow-related functions for ppm

# Shared stow ignore list. Layers of the same package name (e.g. user/git, pde/git)
# accumulate into one list so lower-priority layers skip files stowed by higher ones.
# install() resets it when moving on to a different package name.
PPM_IGNORE_ARGS=()

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
