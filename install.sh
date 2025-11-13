#!/usr/bin/env bash
set -euo pipefail


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

PPM_BIN_FILE=$XDG_BIN_DIR/ppm
PPM_BIN_URL=https://raw.githubusercontent.com/maxcole/ppm/refs/heads/main/ppm


# Source a local copy of the library file or download from a URL
source_lib_file() {
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
  source $PPM_LIB_FILE
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
  # Check for xcode
  # if ! command -v python3 >/dev/null 2>&1; then
  #   debug "ERROR!!"
  #   debug ""
  #   debug "python interpreter not found. Run 'xcode-select --install' from a terminal then rerun this script"
  #   exit 1
  # fi

  # Check for Homebrew
  if ! command -v brew >/dev/null 2>&1; then
    echo "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  fi
  if ! command -v brew >/dev/null 2>&1; then
    debug "ERROR!!"
    debug ""
    debug "brew command not found. Run the brew install script from a terminal then rerun this script"
    exit 1
  fi

  # Check for xcode
  if ! command -v python3 >/dev/null 2>&1; then
    brew install mas
    mas install 497799835 # Install xcode
  fi
}


setup_xdg() {
  mkdir -p $HOME/.cache $HOME/.config $HOME/.local $HOME/.local/bin $HOME/.local/share $HOME/.local/state
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
  source_lib_file
  ensure_deps
  setup_xdg
  install_bin
}

main

# [[ ! -d $CONFIG_DIR/zsh ]] && mkdir -p $CONFIG_DIR/zsh
