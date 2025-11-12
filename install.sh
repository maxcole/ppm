#!/usr/bin/env bash
set -euo pipefail


# The purpose of this file is to:
# 1. check that the dependencies are met
# all: passwordless sudo; packages: curl, wget, stow, etc
# mac: xcode and brew with permissions
# 2. install the library file and the ppm bin script



XDG_BIN_DIR=$HOME/.local/bin
XDG_CACHE_DIR=$HOME/.cache

PPM_CACHE_DIR=$XDG_CACHE_DIR/ppm
PPM_LIB_FILE=$PPM_CACHE_DIR/library.sh
PPM_LIB_URL=https://raw.githubusercontent.com/maxcole/ppm/refs/heads/main/library.sh


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
    if [ ! check_sudo ]; then
      echo "no sudo"
      echo "TODO: also sudoers"
      return
    fi
  elif [[ "$(os)" == "macos" ]]; then
    macos_dep_xcode
    macos_dep_homebrew
  fi

  install_dep "curl" "git" "stow" "wget"
}


macos_dep_xcode() {
  if ! command -v python3 >/dev/null 2>&1; then
    debug "ERROR!!"
    debug ""
    debug "python interpreter not found. Run 'xcode-select --install' from a terminal then rerun this script"
    exit 1
  fi
}


macos_dep_homebrew() {
   echo "TODO: check for brew and install it if not"
}




install_bin() {
  PPM_BIN_FILE=$XDG_BIN_DIR/ppm
  PPM_BIN_URL=https://raw.githubusercontent.com/maxcole/ppm/refs/heads/main/ppm
echo 'hello bin'
  if [ ! -f $PPM_BIN_FILE ]; then
    curl -o $PPM_LIB_FILE $PPM_LIB_URL
  fi
}



#### OLD CODE
# [[ $# -eq 0 ]] && exit 0

#######
# The 'coder' package manager, aka 'cpm'
#
# Two profiles
# 1. remote - export shares, full env, ssh auth key(s); typically linux hosts
# 2. local - mount shares, partial env, ssh private key(s); typically mac hosts
#
# Process for all profiles:
# 1. Install deps (based on os + arch)
# 2. Clone the repos
# 3. Install packages (with functions appropriate on os + arch + profile)
# 3a. zsh basics
# 3b. ssh stuff
#######

# CONFIG_DIR=$HOME/.config
# BIN_DIR=$HOME/.local/bin
# PROJECTS_DIR=$HOME/code/projects
# 
# LIB_FILE=$PROJECTS_DIR/pcs/bootstrap/library.sh
# LIB_URL=https://raw.githubusercontent.com/maxcole/pcs-bootstrap/refs/heads/main/library.sh
# 
# CODE_DIR=$PROJECTS_DIR/rjayroach
# CODE_REPO_PREFIX="git@github.com:maxcole/rjayroach"
# CODE_REPOS=("claude" "coder")
# 
# CODER_PROFILES=("local" "remote")
# CODER_PROFILE_DIR=$CONFIG_DIR/zsh
# CODER_PROFILE_FILE=$CODER_PROFILE_DIR/coder_profile.zsh
# # CODER_PACKAGES_DIR=$CODE_DIR/coder/packages
# CODER_PACKAGES_HOME=$HOME/.cache/ppm
# 
# # Source a local copy of the library file or download from a URL
# if [ ! -f $LIB_FILE ]; then
#   lib_dir=$HOME/.cache/coder
#   mkdir -p $lib_dir
#   LIB_FILE=/$lib_dir/library.sh
#   if [ ! -f $LIB_FILE ]; then # Download and source the script
#     if command -v wget &> /dev/null; then
#       wget -O $LIB_FILE $LIB_URL
#     elif command -v curl &> /dev/null; then
#       curl -o $LIB_FILE $LIB_URL
#     else
#       echo "Install wget or curl to continue."
#       exit 1
#     fi
#   fi
# fi
# source $LIB_FILE


# [[ ! -d $CONFIG_DIR/zsh ]] && mkdir -p $CONFIG_DIR/zsh
# [[ ! -d $BIN_DIR ]] && mkdir -p $BIN_DIR

# prompt_profile
# debug
# install_deps

# main() {
  source_lib_file
  ensure_deps
  setup_xdg
  install_bin
# }

# main
