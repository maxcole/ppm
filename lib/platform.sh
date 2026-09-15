#!/usr/bin/env bash
# Platform: OS/distro detection, and Homebrew's location and ownership
#
# Homebrew supports one owner per installation. The owner installs and upgrades formulas;
# other users run the tools but never write to the prefix.

# Apple silicon macOS and Linux; Intel Macs (/usr/local) are not supported
PPM_BREW_PREFIXES="/opt/homebrew /home/linuxbrew/.linuxbrew"

# macos, or the supported distro family from os-release (ID first, then ID_LIKE)
# Keep in sync with install.sh
platform() {
  if [[ "$OSTYPE" == darwin* ]]; then
    echo "macos"
    return
  fi

  local os_release="${PPM_OS_RELEASE:-/etc/os-release}" candidates="" candidate
  [[ -r "$os_release" ]] && candidates=$(. "$os_release" && echo "${ID:-} ${ID_LIKE:-}")
  for candidate in $candidates; do
    case "$candidate" in
      debian) echo "debian"; return ;;
    esac
  done
  echo "unsupported"
}

# First Homebrew prefix that exists; prints nothing if Homebrew is not installed
# Keep in sync with install.sh
brew_prefix() {
  local prefix
  for prefix in $PPM_BREW_PREFIXES; do
    if [[ -x "$prefix/bin/brew" ]]; then
      echo "$prefix"
      return 0
    fi
  done
  return 0
}

# Put Homebrew on PATH when ppm runs without the user's shell setup (cron, sudo -iu, env -i)
brew_env() {
  command -v brew >/dev/null 2>&1 && return 0
  local prefix
  prefix=$(brew_prefix)
  [[ -n "$prefix" ]] || return 0
  eval "$("$prefix/bin/brew" shellenv bash)"
}

# User that owns a Homebrew installation (its repository dir; on Apple silicon that is the prefix)
# Usage: brew_owner [prefix]   — returns 1 if Homebrew is not installed
brew_owner() {
  local prefix="${1:-$(brew_prefix)}" dir
  [[ -n "$prefix" ]] || return 1
  dir="$prefix/Homebrew"
  [[ -d "$dir" ]] || dir="$prefix"
  if [[ "$(os)" == "macos" ]]; then
    stat -f %Su "$dir"
  else
    stat -c %U "$dir"
  fi
}

# True when the current user owns the Homebrew installation
brew_is_owner() {
  local owner
  owner=$(brew_owner) || return 1
  [[ "$owner" == "$(id -un)" ]]
}

# Succeeds for the owner; otherwise reports who must run <action> and returns 1
# Usage: brew_require_owner "brew install jq"
brew_require_owner() {
  local action="$1" owner
  brew_is_owner && return 0
  if owner=$(brew_owner); then
    ppm_fail "Homebrew is owned by $owner; ask them to run: $action"
  else
    ppm_fail "Homebrew is not installed; it is needed to run: $action"
  fi
  return 1
}

# Refresh Homebrew's formula index at most every HOMEBREW_UPDATE_CACHE_DURATION seconds (owner only)
update_brew_if_needed() {
  if ! command -v brew >/dev/null 2>&1; then
    debug "Homebrew not found; skipping brew update"
    return 0
  fi
  if ! brew_is_owner; then
    debug "Homebrew is owned by $(brew_owner); skipping brew update"
    return 0
  fi

  local cache_duration="${HOMEBREW_UPDATE_CACHE_DURATION:-86400}" # default is 24 hours in seconds
  local cache_file="$PPM_CACHE_HOME/brew_last_update"

  if [[ ! -f "$cache_file" ]] || [[ $(($(date +%s) - $(cat "$cache_file"))) -gt $cache_duration ]]; then
    [[ ! -d $PPM_CACHE_HOME ]] && mkdir -p $PPM_CACHE_HOME
    brew update
    date +%s > "$cache_file"
  fi
}
