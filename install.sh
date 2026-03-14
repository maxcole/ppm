#!/usr/bin/env bash
set -euo pipefail
#
# PPM Install Script
#
# WHAT THIS SCRIPT DOES:
#   1. Installs dependencies via apt (Linux) or Homebrew (macOS)
#   2. Clones ppm repo to ~/.local/share/ppm/ppm and symlinks script to ~/.local/bin/ppm
#   3. Clones your repo (if --repo provided) to ~/.local/share/ppm/<repo-name>
#   4. Creates config files (ppm.conf, sources.list) in your repo's ppm package
#   5. Symlinks config files to ~/.config/ppm/
#   6. Runs 'ppm update' and 'ppm install' for specified packages
#
# FILES CREATED:
#   ~/.local/share/ppm/ppm/           - cloned ppm repo
#   ~/.local/bin/ppm                 - symlink to repo's ppm script
#   ~/.config/ppm/ppm.conf           - symlink to repo config
#   ~/.config/ppm/sources.list       - symlink to repo sources
#   ~/.local/share/ppm/<repo>/       - cloned repo (if --repo provided)
#
# EXTERNAL FETCHES:
#   https://github.com/maxcole/ppm.git (cloned to ~/.local/share/ppm/ppm)
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
export PATH="$BIN_DIR:$PATH"

XDG_CONFIG_HOME=$HOME/.config
XDG_DATA_HOME=$HOME/.local/share

PPM_CONFIG_HOME=$XDG_CONFIG_HOME/ppm
PPM_DATA_HOME=$XDG_DATA_HOME/ppm

PPM_REPO_URL=https://github.com/maxcole/ppm.git
PPM_REPO_DIR=$PPM_DATA_HOME/ppm
PPM_USER_URL=https://raw.githubusercontent.com/maxcole/user-ppm/refs/heads/main
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


arch() {
  local arch
  arch="$(uname -m)"
  case "$arch" in
    x86_64)        echo "amd64" ;;
    aarch64|arm64) echo "arm64" ;;
    *) echo "Unsupported architecture: $arch" >&2; exit 1 ;;
  esac
}


install_yq() {
  if command -v yq >/dev/null 2>&1 && yq --version 2>&1 | grep -q 'mikefarah/yq'; then
    return 0
  fi

  local url="https://github.com/mikefarah/yq/releases/latest/download/yq_linux_$(arch)"
  mkdir -p "$BIN_DIR"
  curl -fsSL "$url" -o "$BIN_DIR/yq"
  chmod +x "$BIN_DIR/yq"
}


setup_deps() {
  if [[ "$(os)" == "linux" ]]; then
    setup_deps_linux
    sudo apt install curl git stow -y
    install_yq
  elif [[ "$(os)" == "macos" ]]; then
    setup_deps_macos
    eval "$(/opt/homebrew/bin/brew shellenv zsh)"
    brew install git stow wget yq
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


install_ppm() {
  mkdir -p $BIN_DIR $PPM_DATA_HOME $PPM_CONFIG_HOME
  if [[ ! -d "$PPM_REPO_DIR" ]]; then
    git clone "$PPM_REPO_URL" "$PPM_REPO_DIR"
  fi
  ln -sf "$PPM_REPO_DIR/ppm" "$BIN_DIR/ppm"
}


install_ppm_configs() {
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
  ppm src add --top $repo_url
  ppm update
  repo_name=$(basename "$repo_url" .git)
  ppm install -f $repo_name/ppm
}


install_packages() {
  local packages=("$@")
  if [[ "$(os)" == "macos" ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  fi
  for pkg in "${packages[@]}"; do
    ppm install "$pkg"
  done
  # stow ppm.zsh and install ppm completions
  ppm install ppm/ppm
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
  install_ppm
  install_ppm_configs
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
install_ppm
install_ppm_configs
[[ -n "$repo_url" ]] && install_repo
ppm update
install_packages "${packages[@]}"
