#!/usr/bin/env bash

post_install() {
  local psm_config="${XDG_CONFIG_HOME:-$HOME/.config}/psm"
  local psm_data="${XDG_DATA_HOME:-$HOME/.local/share}/psm"

  # Create PSM config directory
  mkdir -p "$psm_config"

  # Create default sources.list if it doesn't exist
  if [[ ! -f "$psm_config/sources.list" ]]; then
    cat > "$psm_config/sources.list" <<'EOF'
# PSM service sources
# Format: <git-url>  <alias>
# Add repos with: psm src add <git-url>
EOF
    user_message "Created $psm_config/sources.list\nAdd service repos with: psm src add <git-url>"
  fi

  # Create PSM data directory
  mkdir -p "$psm_data"
}
