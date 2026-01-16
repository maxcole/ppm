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

# The purpose of this file is to:
# 1. check that the dependencies are met
# all: packages: curl, wget, stow, etc
# linux: passwordless sudo
# mac: xcode and brew with permissions
# 2. download the ppm script to BIN_DIR
# 3. create PPM_CACHE_HOME and PPM_SOURCES_FILE

BIN_DIR=$HOME/.local/bin

# XDG directories
XDG_CONFIG_HOME=$HOME/.config
XDG_DATA_HOME=$HOME/.local/share

# PPM directories
PPM_CONFIG_HOME=$XDG_CONFIG_HOME/ppm
PPM_DATA_HOME=$XDG_DATA_HOME/ppm

# PPM files
PPM_BIN_FILE=$BIN_DIR/ppm
PPM_BIN_URL=https://raw.githubusercontent.com/maxcole/ppm/refs/heads/main/ppm
PPM_SOURCES_FILE=$PPM_CONFIG_HOME/sources.list


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


ensure_deps_linux() {
  # Check if user has sudo ALL privileges without prompting
  if sudo -n -l 2>/dev/null | grep -q "(ALL) ALL"; then
    return
  fi
  echo "enable sudo ALL for this user before continuing"
  exit 1
}


ensure_deps_macos() {
  # Pre-authorize sudo at the start
  if ! sudo -n true 2>/dev/null; then
    echo "This script requires sudo access to install xcode. Please enter your password:"
    sudo -v
  fi

  # Check for Homebrew
  if ! command -v brew >/dev/null 2>&1; then
    echo "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    eval "$(/opt/homebrew/bin/brew shellenv)"
  fi
}


# Ensure dependencies
ensure_deps() {
  if [[ "$(os)" == "linux" ]]; then
    ensure_deps_linux
    sudo apt install curl git stow -y
  elif [[ "$(os)" == "macos" ]]; then
    ensure_deps_macos
    brew install git stow wget
  fi
}


setup_ppm() {
  mkdir -p $BIN_DIR
  if [ ! -f $PPM_BIN_FILE ]; then
    curl -o $PPM_BIN_FILE $PPM_BIN_URL
    chmod +x $PPM_BIN_FILE
  fi
  mkdir -p $PPM_DATA_HOME $PPM_CONFIG_HOME
  touch $PPM_SOURCES_FILE
}


main() {
  ensure_deps
  setup_ppm
}

main
