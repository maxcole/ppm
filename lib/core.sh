#!/usr/bin/env bash
# Core utility functions for ppm

# Detect the CPU architecture
arch() {
  local arch=$(uname -m)

  if [[ "$arch" == "aarch64" || "$arch" == "arm64" ]]; then
    echo "arm64"
  else
    echo "amd64"
  fi
}

# Detect the OS
os() {
  if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    echo "linux"
  elif [[ "$OSTYPE" == "darwin"* ]]; then
    echo "macos"
  else
    echo "unsupported"
  fi
}

# search in file and add/remove as requested
add_to_file() {
  local file="$1" dir="$(dirname "$1")"
  shift

  [[ -d "$dir" ]] || mkdir -p $dir
  [[ -f "$file" ]] || touch "$file"

  for string in "$@"; do
    _string_in_file "$string" "$file" || echo "$string" >> "$file"
  done
}

remove_from_file() {
  local file="$1"
  shift
  [[ -f "$file" ]] || return 0

  for string in "$@"; do
    if _string_in_file "$string" "$file"; then
      _sed_inplace "/^$(printf '%s' "$string" | sed 's/[^^]/[&]/g; s/\^/\\^/g')$/d" "$file"
    fi
  done
}

_string_in_file() {
  local string="$1" file="$2"
  grep -qxF "$string" "$file" 2>/dev/null
}

_sed_inplace() {
  local pattern="$1" file="$2"

  # Resolve symlink to actual file
  if [[ -L "$file" ]]; then
    local link_target=$(readlink "$file")
    if [[ "$link_target" == /* ]]; then
      file="$link_target"
    else
      file="$(dirname "$file")/$link_target"
    fi
  fi

  if [[ "$(os)" == "macos" ]]; then
    sed -i '' "$pattern" "$file"
  else
    sed -i "$pattern" "$file"
  fi
}

# Creates symlinks in target_dir for each entry in the list
create_symlinks() {
  local target_dir="$1"
  shift
  local entries=("$@")

  for entry in "${entries[@]}"; do
    local name=$(basename "$entry")
    local link_path="$target_dir/$name"
    if [ ! -L "$link_path" ]; then
      ln -s "$entry" "$link_path"
    fi
  done
}

# Check if entry is a git URL (not a local path)
is_git_url() {
  [[ "$1" == git@* || "$1" == *://* ]]
}

# Install dependencies using the OS specific package manager (apt or homebrew)
install_dep() {
  if [[ "$(os)" == "linux" ]]; then
    sudo apt install "$@" -y
  elif [[ "$(os)" == "macos" ]]; then
    local cask_flag=""
    [[ "${1:-}" == "--cask" ]] && { cask_flag="--cask"; shift; }
    for dep in "$@"; do
      if ! brew list $cask_flag "$dep" &>/dev/null; then
        brew install $cask_flag "$dep"
      elif brew outdated $cask_flag --quiet | grep -q "^${dep}$"; then
        brew upgrade $cask_flag "$dep"
      fi
    done
  fi
}

# Debug logging — enabled by --debug flag
PPM_DEBUG=${PPM_DEBUG:-false}

debug() {
  $PPM_DEBUG && echo -e "[DEBUG] $*" >&2 || true
}

# User message aggregation — packages call user_message() during install
PPM_MSG_FILE=$(mktemp /tmp/ppm-messages.XXXXXX)
trap 'rm -f "$PPM_MSG_FILE"' EXIT

# Set by installer() before sourcing each package's install.sh
PPM_CURRENT_PACKAGE=""

user_message() {
  local prefix=""
  [[ -n "$PPM_CURRENT_PACKAGE" ]] && prefix="[$PPM_CURRENT_PACKAGE] "
  # Join args, stripping leading whitespace from each so backslash continuations work
  local msg=""
  for arg in "$@"; do
    msg="${msg}${arg#"${arg%%[![:space:]]*}"}"
  done
  echo "${prefix}${msg}" >> "$PPM_MSG_FILE"
}

flush_user_messages() {
  if [[ -s "$PPM_MSG_FILE" ]]; then
    echo ""
    echo "=== Package Messages ==="
    while IFS= read -r line; do
      # Extract prefix length for indenting continuation lines
      local padding=""
      if [[ "$line" =~ ^\[.*\]\  ]]; then
        local prefix_len=${#BASH_REMATCH}
        padding=$(printf '%*s' "$prefix_len" '')
      fi
      # Expand \n then indent continuation lines
      local expanded
      expanded=$(printf '%b' "$line")
      local first=true
      while IFS= read -r subline; do
        if $first; then
          echo "$subline"
          first=false
        else
          echo "${padding}${subline}"
        fi
      done <<< "$expanded"
    done < "$PPM_MSG_FILE"
    echo "========================"
  fi
  rm -f "$PPM_MSG_FILE"
}

# Called by packages to signal a non-fatal install failure.
# Logs the error immediately to stderr and queues it for end-of-run display.
# Usage (in a package install.sh):
#   ppm_fail "No pre-built binaries for arm64 Linux"
#   return
ppm_fail() {
  local prefix=""
  [[ -n "$PPM_CURRENT_PACKAGE" ]] && prefix="[$PPM_CURRENT_PACKAGE] "
  echo -e "${prefix}ERROR: $*" >&2
  user_message "ERROR: $*"
  return 1
}

# Generate and install a zsh completion file
# Usage: install_completion "command completion-args..."
install_completion() {
  [[ -z "${PPM_FPATH:-}" ]] && return
  local cmd="$1"
  local output_file="$PPM_FPATH/_${cmd%% *}"

  mkdir -p "$PPM_FPATH"
  if ! $cmd > "$output_file"; then
    user_message "Failed to generate completion for ${cmd%% *}"
    rm -f "$output_file"
    return 1
  fi
}
