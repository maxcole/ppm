#!/usr/bin/env bash
# Generic asset installer/remover — backend-agnostic

# Install a single resolved asset
# Called by install() for each entry in RESOLVE_ORDER
# Arguments: repo_name asset_name asset_dir
install_single_package() {
  local repo_name="$1" asset_name="$2" asset_dir="$3"

  PPM_CURRENT_PACKAGE="$repo_name/$asset_name"
  echo "Install $repo_name/$asset_name"
  debug "Asset dir: $asset_dir"

  # No hook script — just run profile install, track, and continue
  if [[ ! -f "$asset_dir/$PPM_ASSET_HOOK" ]]; then
    PROFILE_STOWED_FILES=""
    profile_install "$asset_dir" "$asset_name"
    meta_cleanup_stale "$repo_name" "$asset_name" "$asset_dir" "$PROFILE_STOWED_FILES"
    meta_mark_installed "$repo_name" "$asset_name" "$asset_dir" "$PROFILE_STOWED_FILES"
    return
  fi

  # pre_install hook
  (
    source "$asset_dir/$PPM_ASSET_HOOK"
    if type pre_install &>/dev/null && [[ -z "${config_flag:-}" ]]; then
      pre_install
    fi
  )

  # Profile-specific install step
  PROFILE_STOWED_FILES=""
  profile_install "$asset_dir" "$asset_name"

  # Clean up stale files from previous version
  meta_cleanup_stale "$repo_name" "$asset_name" "$asset_dir" "$PROFILE_STOWED_FILES"

  # OS-specific install + post_install
  (
    source "$asset_dir/$PPM_ASSET_HOOK"

    local func_name="install_$(os)"
    if type "$func_name" &>/dev/null && [[ -z "${config_flag:-}" ]]; then
      "$func_name"
    fi

    if type post_install &>/dev/null && [[ -z "${config_flag:-}" ]]; then
      post_install
    fi
  )

  # Write tracker after all phases succeed
  meta_mark_installed "$repo_name" "$asset_name" "$asset_dir" "$PROFILE_STOWED_FILES"
}

# Remove assets by name, searching repos in source order
# Arguments: asset_spec [asset_spec ...]
remover() {
  collect_repos
  local requested_assets=("$@")

  for asset in "${requested_assets[@]}"; do
    local asset_repo=$(dirname "$asset") asset_name=$(basename "$asset")
    [[ "$asset" == */* ]] && local single_repo="true" || local single_repo="false"

    for i in "${!REPO_URLS[@]}"; do
      local repo_name="${REPO_NAMES[$i]}"
      [[ "$single_repo" == "true" && "$repo_name" != "$asset_repo" ]] && continue

      local asset_dir="$PPM_DATA_HOME/$repo_name/$PPM_ASSET_DIR/$asset_name"
      [[ ! -d "$asset_dir" ]] && continue
      echo "Remove $repo_name/$asset_name"

      local has_hook
      [[ -f "$asset_dir/$PPM_ASSET_HOOK" ]] && has_hook=true || has_hook=false

      # Phase 1: pre_remove hook
      if $has_hook; then
        (
          source "$asset_dir/$PPM_ASSET_HOOK"
          type pre_remove &>/dev/null && pre_remove || true
        )
      fi

      # Phase 2: profile-specific remove
      profile_remove "$asset_dir" "$asset_name"

      # Phase 3: OS-specific remove + post_remove
      if $has_hook; then
        (
          source "$asset_dir/$PPM_ASSET_HOOK"
          func_name="remove_$(os)"
          type $func_name &>/dev/null && $func_name || true
          type post_remove &>/dev/null && post_remove || true
        )
      fi

      # Phase 4: remove tracker
      meta_mark_removed "$repo_name" "$asset_name"
    done
  done
}

# Default profile functions — no-op if no backend loaded
if ! type profile_install &>/dev/null; then
  profile_install() {
    debug "No profile_install defined for asset dir '$PPM_ASSET_DIR' — skipping"
    PROFILE_STOWED_FILES=""
  }
fi

if ! type profile_remove &>/dev/null; then
  profile_remove() {
    debug "No profile_remove defined for asset dir '$PPM_ASSET_DIR' — skipping"
  }
fi
