#!/usr/bin/env bash
# Package backend — stow-based dotfile management

# Install a package asset: stow its home/ directory into $HOME
# Called by install_single_package after pre_install and before post_install
# Arguments: asset_dir asset_name
profile_install() {
  local asset_dir="$1" asset_name="$2"
  local ignore_args=()

  stow_subdir "$asset_dir" "home"
  [[ -n "${PPM_GROUP_ID:-}" ]] && stow_subdir "$asset_dir" "$PPM_GROUP_ID"

  # Collect stowed file list for tracking
  local stowed_files=""
  [[ -d "$asset_dir/home" ]] && stowed_files=$(package_links "$asset_dir/home")
  if [[ -n "${PPM_GROUP_ID:-}" && -d "$asset_dir/$PPM_GROUP_ID" ]]; then
    local group_files
    group_files=$(package_links "$asset_dir/$PPM_GROUP_ID")
    [[ -n "$group_files" ]] && stowed_files="${stowed_files}"$'\n'"${group_files}"
  fi

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
