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
PPM_BASE_URL=https://raw.githubusercontent.com/maxcole/ppm/refs/heads/main
PPM_BIN_FILE=$BIN_DIR/ppm
PPM_CONFIG_FILE=$PPM_CONFIG_HOME/ppm.conf
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


# Setup dependencies
setup_deps() {
  if [[ "$(os)" == "linux" ]]; then
    setup_deps_linux
    sudo apt install curl git stow -y
  elif [[ "$(os)" == "macos" ]]; then
    setup_deps_macos
    brew install git stow wget
  fi
}


setup_deps_linux() {
  # Check if user has sudo ALL privileges without prompting
  if sudo -n -l 2>/dev/null | grep -q "(ALL) ALL"; then
    return
  fi
  echo "enable sudo ALL for this user before continuing"
  exit 1
}


setup_deps_macos() {
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


install() {
  local repo_url="${1:-}" user_id=$(whoami)-ppm

  if [[ -n "$repo_url" ]]; then
    user_id=$(basename "$repo_url" .git)
  fi

  local repo_dir="$PPM_DATA_HOME/$user_id"
  local repo_config_dir="$repo_dir/packages/ppm/home/.config/ppm"

  if [[ -n "$repo_url" ]]; then
    [[ ! -d "$repo_dir" ]] && git clone "$repo_url" "$repo_dir"
  fi
  mkdir -p "$repo_config_dir"

  install_config
  install_script
  install_zsh
}


install_config() {
  if [[ ! -f "$repo_config_dir/ppm.conf" ]]; then
    curl -fsSL "$PPM_BASE_URL/ppm.conf" -o "$repo_config_dir/ppm.conf"
  fi

  if [[ ! -f "$repo_config_dir/sources.list" ]]; then
    curl -fsSL "$PPM_BASE_URL/sources.list" | sed "s/{user_id}/$user_id/" > "$repo_config_dir/sources.list"
  fi

  if [[ ! -f "$repo_config_dir/sources.list" ]]; then
    echo -e "${RED}Error: sources.list not found at $repo_config_dir/sources.list${NC}"
    exit 1
  fi

  if [[ ! -L "$PPM_SOURCES_FILE" ]]; then
    rm -f "$PPM_SOURCES_FILE"
    ln -s "$repo_config_dir/sources.list" "$PPM_SOURCES_FILE"
  fi

  if [[ -f "$repo_config_dir/ppm.conf" && ! -L "$PPM_CONFIG_FILE" ]]; then
    rm -f "$PPM_CONFIG_FILE"
    ln -s "$repo_config_dir/ppm.conf" "$PPM_CONFIG_FILE"
  fi
}


install_script() {
  mkdir -p $BIN_DIR
  if [ ! -f $PPM_BIN_FILE ]; then
    curl -fsSL "$PPM_BASE_URL/ppm" -o $PPM_BIN_FILE
    chmod +x $PPM_BIN_FILE
  fi
  mkdir -p $PPM_DATA_HOME $PPM_CONFIG_HOME
}


install_zsh() {
  if [[ "$(os)" == "macos" ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  fi
  $PPM_BIN_FILE update
  $PPM_BIN_FILE install zsh
  echo -e "\n${GREEN}Installation complete!${NC}"
  echo -e "Open a new shell or run: ${CYAN}source ~/.zshrc${NC}"
}


skip_deps=false
script_only=false
repo_url="${PPM_REPO_URL:-}"

for arg in "$@"; do
  case "$arg" in
    --skip-deps) skip_deps=true ;;
    --script-only) script_only=true ;;
    git@*|https://*) repo_url="$arg" ;;
  esac
done

if [[ "$script_only" == true ]]; then
  install_script
elif [[ "$repo_url" =~ ^(git@|https://) ]]; then
  [[ "$skip_deps" == false ]] && setup_deps
  install "$repo_url"
else
  [[ "$skip_deps" == false ]] && setup_deps
  install
fi
