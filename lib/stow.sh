#!/usr/bin/env bash
# Stow-related functions for ppm

# Stow a package subdirectory and collect files for ignore_args
# Requires ignore_args array to be defined in caller's scope
stow_subdir() {
  local pkg_dir="$1" subdir="$2"
  local full_path="$pkg_dir/$subdir"

  [[ -d "$full_path" ]] || return 0
  debug "Stowing $subdir from $pkg_dir"

  # If force mode, remove conflicting files first
  $force && force_remove_conflicts "$full_path"

  stow --no-folding ${ignore_args[@]+"${ignore_args[@]}"} -d "$pkg_dir" -t "$HOME" "$subdir"

  while IFS= read -r file; do
    if [[ -n "$file" ]]; then
      local escaped="${file//./\\.}"
      ignore_args+=("--ignore=^${escaped}\$")
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
# Requires ignore_args array to be defined in caller's scope
force_remove_conflicts() {
  local full_path="$1"

  while IFS= read -r file; do
    [[ -z "$file" ]] && continue

    # Check if this file is in ignore_args (already stowed from previous subdir)
    local escaped="${file//./\\.}"
    local is_ignored=false
    if [[ ${#ignore_args[@]} -gt 0 ]]; then
      for arg in "${ignore_args[@]}"; do
        [[ "$arg" == "--ignore=^${escaped}\$" ]] && { is_ignored=true; break; }
      done
    fi

    # Remove the file from $HOME if it exists and isn't ignored
    if ! $is_ignored && [[ -e "$HOME/$file" || -L "$HOME/$file" ]]; then
      rm -f "$HOME/$file"
    fi
  done < <(package_links "$full_path")
}
