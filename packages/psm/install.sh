#!/usr/bin/env bash

post_install() {
  install_completion "psm completion zsh"
  local psm_config="${XDG_CONFIG_HOME:-$HOME/.config}/psm"
  local psm_data="${XDG_DATA_HOME:-$HOME/.local/share}/psm"

  # Create PSM config directory
  mkdir -p "$psm_config"

  # Create default sources.list with psm-ppm if it doesn't exist
  if [[ ! -f "$psm_config/sources.list" ]]; then
    cat > "$psm_config/sources.list" <<'EOF'
git@github.com:maxcole/psm-ppm  psm-ppm
EOF
    user_message "Created $psm_config/sources.list with default service source"
    user_message "Run: psm update  to fetch service definitions"
  fi

  # Create PSM data directory
  mkdir -p "$psm_data"
}
