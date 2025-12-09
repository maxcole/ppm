#!/usr/bin/env bash
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# ASCII Art Banner
echo -e "${CYAN}"
cat << "EOF"
 ____  ____  __  __
|  _ \|  _ \|  \/  |
| |_) | |_) | |\/| |
|  __/|  __/| |  | |
|_|   |_|   |_|  |_|

EOF
echo -e "${CYAN}Personal Package Manager${NC}"
exit

# The purpose of this file is to:
# 1. check that the dependencies are met
# all: passwordless sudo; packages: curl, wget, stow, etc
# mac: xcode and brew with permissions
# 2. install the library file and the ppm bin script


# XDG directories
XDG_CACHE_DIR=$HOME/.cache

# PPM directories and files
PPM_CACHE_DIR=$XDG_CACHE_DIR/ppm

PPM_LIB_FILE=$PPM_CACHE_DIR/library.sh
PPM_LIB_URL=https://raw.githubusercontent.com/maxcole/ppm/refs/heads/main/library.sh


# Install a local copy of the library file from a URL
ensure_lib_file() {
  if [ ! -f $PPM_LIB_FILE ]; then
    mkdir -p $PPM_CACHE_DIR
    if command -v wget &> /dev/null; then
      wget -O $PPM_LIB_FILE $PPM_LIB_URL
    elif command -v curl &> /dev/null; then
      curl -o $PPM_LIB_FILE $PPM_LIB_URL
    else
      echo "Install wget or curl to continue."
      exit 1
    fi
  fi
}


source_lib_file() {
  source $PPM_LIB_FILE
  PPM_BIN_FILE=$XDG_BIN_DIR/ppm
  PPM_BIN_URL=https://raw.githubusercontent.com/maxcole/ppm/refs/heads/main/ppm
}


# Ensure dependencies
ensure_deps() {
  if [[ "$(os)" == "linux" ]]; then
    ensure_deps_linux
  elif [[ "$(os)" == "macos" ]]; then
    ensure_deps_macos
  fi

  install_dep "curl" "git" "stow" "wget"
}


ensure_deps_linux() {
  if [ ! check_sudo ]; then
    debug "ERROR!!"
    debug ""
    debug "enable sudo for this user"
    exit 1
  fi
}


ensure_deps_macos() {
  # Check for Homebrew
  if ! command -v brew >/dev/null 2>&1; then
    echo "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    # echo >> $HOME/.zprofile
    # echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> $HOME/.zprofile
    eval "$(/opt/homebrew/bin/brew shellenv)"
  fi
}


setup_xdg() {
  mkdir -p $XDG_BIN_DIR $XDG_CACHE_DIR $XDG_CONFIG_DIR
  mkdir -p $HOME/.local/share $HOME/.local/state
  # mkdir -p $XDG_CONFIG_DIR/zsh
}


install_bin() {
  if [ ! -f $PPM_BIN_FILE ]; then
    curl -o $PPM_BIN_FILE $PPM_BIN_URL
    chmod +x $PPM_BIN_FILE
  fi
  mkdir -p $PPM_CONFIG_DIR
  touch $PPM_SOURCES_FILE
}


main() {
  ensure_lib_file
  source_lib_file
  ensure_deps
  setup_xdg
  install_bin
}

main
