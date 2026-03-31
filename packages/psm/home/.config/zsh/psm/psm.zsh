# psm.zsh — Podman Service Manager shell function
# Sets PSM-specific env vars and delegates to the ppm engine

if ! command -v ppm >/dev/null 2>&1; then
  return
fi

psm() {
  if [[ "${1:-}" == "cd" ]]; then
    shift
    local verbose_flag=""
    [[ "${1:-}" == "-v" ]] && { verbose_flag="-v"; shift; }
    if [[ $# -eq 0 ]]; then
      cd "${XDG_DATA_HOME:-$HOME/.local/share}/psm"
    else
      local svc_path
      svc_path=$(
        PPM_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}/psm" \
        PPM_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}/psm" \
        PPM_ASSET_DIR="services" \
        PPM_ASSET_META="service.yml" \
        command ppm path $verbose_flag "$@"
      ) || return $?
      cd "$svc_path"
    fi
  else
    PPM_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}/psm" \
    PPM_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}/psm" \
    PPM_ASSET_DIR="services" \
    PPM_ASSET_LABEL="service" \
    PPM_ASSET_META="service.yml" \
    command ppm "$@"
  fi
}

# Load PSM completions
if command -v ppm >/dev/null 2>&1; then
  eval "$(PPM_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}/psm" \
    PPM_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}/psm" \
    PPM_ASSET_DIR=services \
    PPM_ASSET_LABEL=service \
    PPM_ASSET_META=service.yml \
    command ppm completion zsh 2>/dev/null)"
fi
