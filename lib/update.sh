#!/usr/bin/env bash
# Periodic update timer functions for ppm

# Update the homebrew cache periodically
update_brew_if_needed() {
  local cache_duration="${HOMEBREW_UPDATE_CACHE_DURATION:-86400}" # default is 24 hours in seconds
  local cache_file="$PPM_CACHE_HOME/brew_last_update"

  if [[ ! -f "$cache_file" ]] || [[ $(($(date +%s) - $(cat "$cache_file"))) -gt $cache_duration ]]; then
    [[ ! -d $PPM_CACHE_HOME ]] && mkdir -p $PPM_CACHE_HOME
    brew update
    date +%s > "$cache_file"
  fi
}

# Auto-update repos if cache duration has elapsed
update_ppm_if_needed() {
  local cache_duration="${PPM_UPDATE_CACHE_DURATION:-86400}"
  local cache_file="$PPM_CACHE_HOME/ppm_last_update"

  if [[ ! -f "$cache_file" ]] || [[ $(($(date +%s) - $(cat "$cache_file"))) -gt $cache_duration ]]; then
    [[ ! -d "$PPM_CACHE_HOME" ]] && mkdir -p "$PPM_CACHE_HOME"
    debug "PPM repos stale, running update"
    if update; then
      date +%s > "$cache_file"
    else
      debug "PPM update incomplete, timer not reset"
    fi
  fi
}
