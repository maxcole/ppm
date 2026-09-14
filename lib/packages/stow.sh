#!/usr/bin/env bash
# Package backend — stow-based dotfile management

# Install a package asset: stow its home/ directory into $HOME
# Called by install_single_package after pre_install and before post_install
# Files already in PPM_IGNORE_ARGS (owned by a higher-priority layer) are skipped
# Arguments: asset_dir asset_name
profile_install() {
  local asset_dir="$1" asset_name="$2"
  local stowed_files="" subdir file

  for subdir in home ${PPM_GROUP_ID:-}; do
    [[ -d "$asset_dir/$subdir" ]] || continue

    # Track only the files this layer actually stows
    while IFS= read -r file; do
      if [[ -n "$file" ]] && ! is_stow_ignored "$file"; then
        stowed_files="${stowed_files:+${stowed_files}$'\n'}${file}"
      fi
    done < <(package_links "$asset_dir/$subdir")

    stow_subdir "$asset_dir" "$subdir"
  done

  # Return stowed files via global (subshell-safe alternative to return values)
  PROFILE_STOWED_FILES="$stowed_files"
}

# Remove a package asset: unstow its home/ directory from $HOME
# Called by remover after pre_remove and before post_remove
# Arguments: asset_dir asset_name
profile_remove() {
  local asset_dir="$1" asset_name="$2"

  if [[ -d "$asset_dir/home" ]]; then
    stow -D -d "$asset_dir" -t "$HOME" home
  fi
  if [[ -n "${PPM_GROUP_ID:-}" && -d "$asset_dir/$PPM_GROUP_ID" ]]; then
    stow -D -d "$asset_dir" -t "$HOME" "$PPM_GROUP_ID"
  fi
}
