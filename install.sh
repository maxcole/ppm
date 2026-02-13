#!/usr/bin/env bash
set -euo pipefail
#
# PPM Install Script
#
# WHAT THIS SCRIPT DOES:
#   1. Installs dependencies via apt (Linux) or Homebrew (macOS)
#   2. Downloads the ppm script to ~/.local/bin/ppm
#   3. Clones your repo (if --repo provided) to ~/.local/share/ppm/<repo-name>
#   4. Creates config files (ppm.conf, sources.list) in your repo's ppm package
#   5. Symlinks config files to ~/.config/ppm/
#   6. Runs 'ppm update' and 'ppm install' for specified packages
#
# FILES CREATED:
#   ~/.local/bin/ppm                 - the ppm executable
#   ~/.config/ppm/ppm.conf           - symlink to repo config
#   ~/.config/ppm/sources.list       - symlink to repo sources
#   ~/.local/share/ppm/<repo>/       - cloned repo (if --repo provided)
#
# EXTERNAL FETCHES:
#   https://raw.githubusercontent.com/maxcole/ppm/refs/heads/main/ppm
#   https://raw.githubusercontent.com/maxcole/ppm/refs/heads/main/ppm.conf
#   https://raw.githubusercontent.com/maxcole/ppm/refs/heads/main/sources.list
#   https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh (macOS only)
#
# SUDO USAGE:
#   Linux: requires passwordless sudo for apt install
#   macOS: prompts for sudo to install Xcode CLI tools
#

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

echo -e "${CYAN}"
cat << "EOF"
 ____  ____  __  __
|  _ \|  _ \|  \/  |
| |_) | |_) | |\/| |
|  __/|  __/| |  | |
|_|   |_|   |_|  |_|

EOF
echo -e "${CYAN}Personal Package Manager${NC}"

BIN_DIR=$HOME/.local/bin

XDG_CONFIG_HOME=$HOME/.config
XDG_DATA_HOME=$HOME/.local/share

PPM_CONFIG_HOME=$XDG_CONFIG_HOME/ppm
PPM_DATA_HOME=$XDG_DATA_HOME/ppm

PPM_BASE_URL=https://raw.githubusercontent.com/maxcole/ppm/refs/heads/main
PPM_USER_URL=https://raw.githubusercontent.com/maxcole/user-ppm/refs/heads/main
PPM_BIN_FILE=$BIN_DIR/ppm
PPM_CONFIG_FILE=$PPM_CONFIG_HOME/ppm.conf
PPM_SOURCES_FILE=$PPM_CONFIG_HOME/sources.list


os() {
  if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    echo "linux"
  elif [[ "$OSTYPE" == "darwin"* ]]; then
    echo "macos"
  else
    echo "unsupported"
  fi
}


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
  if sudo -n -l 2>/dev/null | grep -q "(ALL) NOPASSWD: ALL"; then return; fi

  echo "Enable passwordless sudo ALL for this user before continuing"
  exit 1
}


setup_deps_macos() {
  if ! sudo -n true 2>/dev/null; then
    echo "This script requires sudo access to install xcode. Please enter your password:"
    sudo -v
  fi
  if ! command -v brew >/dev/null 2>&1; then
    echo "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
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


install_config() {
  local pkg_path=packages/ppm/home/.config/ppm

  for config_file in ppm.conf sources.list; do
    if [[ ! -f "$PPM_CONFIG_HOME/$config_file" ]]; then
      curl -fsSL "$PPM_USER_URL/$pkg_path/$config_file" -o "$PPM_CONFIG_HOME/$config_file"
    fi
  done

  if [[ ! -f "$PPM_CONFIG_HOME/ppm.local.conf" ]]; then
    echo "PPM_GROUP_ID=$(os)" > "$PPM_CONFIG_HOME/ppm.local.conf"
  fi
}


install_repo() {
  $PPM_BIN_FILE src add --top $repo_url
  $PPM_BIN_FILE update
  repo_name=$(basename "$repo_url" .git)
  $PPM_BIN_FILE install -f $repo_name/ppm
}


install_packages() {
  local packages=("$@")
  if [[ "$(os)" == "macos" ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  fi
  for pkg in "${packages[@]}"; do
    $PPM_BIN_FILE install "$pkg"
  done
  echo -e "\n${GREEN}Installation complete!${NC}"
  echo -e "Open a new shell or run: ${CYAN}source ~/.zshrc${NC}"
}


skip_deps=false
script_only=false
repo_url="${PPM_INSTALL_REPO:-}"
packages=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-deps) skip_deps=true; shift ;;
    --script-only) script_only=true; shift ;;
    --repo) repo_url="$2"; shift 2 ;;
    *) packages+=("$1"); shift ;;
  esac
done

if [[ "$script_only" == true ]]; then
  install_script
  install_config
  exit 0
fi

if [[ ${#packages[@]} -eq 0 && -n "${PPM_INSTALL_PACKAGES:-}" ]]; then
  IFS=' ' read -ra packages <<< "$PPM_INSTALL_PACKAGES"
fi
if [[ ${#packages[@]} -eq 0 ]]; then
  packages=(zsh)
fi

[[ "$skip_deps" == false ]] && setup_deps
mkdir -p $HOME/.ssh
ssh-keyscan github.com >> $HOME/.ssh/known_hosts 2>/dev/null
install_script
install_config
[[ -n "$repo_url" ]] && install_repo
$PPM_BIN_FILE update
install_packages "${packages[@]}"
