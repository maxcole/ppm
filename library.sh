
PPM_CONFIG_DIR=$HOME/.config/ppm
PPM_SOURCES_FILE=$PPM_CONFIG_DIR/sources.list


# ZSH_CONFIG_DIR=$XDG_CONFIG_DIR/zsh

# PROJECTS_DIR=$HOME/code/projects

# LIB_FILE=$PROJECTS_DIR/pcs/bootstrap/library.sh

# CODE_DIR=$PROJECTS_DIR/rjayroach
# CODE_REPO_PREFIX="git@github.com:maxcole/rjayroach"
# CODE_REPOS=("claude" "coder")

# CODER_PROFILES=("local" "remote")
# CODER_PROFILE_DIR=$ZSH_CONFIG_DIR
# CODER_PROFILE_FILE=$ZSH_CONFIG_DIR/coder_profile.zsh
# CODER_PACKAGES_DIR=$CODE_DIR/coder/packages

# prompt_profile() {
#   if [[ -z "${CODER_PROFILE:-}" ]]; then
#     if [ -f $CODER_PROFILE_FILE ]; then
#       source $CODER_PROFILE_FILE
#     else
#       while true; do
#         read -p "Coder profile [${CODER_PROFILES[*]}]: " CODER_PROFILE
#         if [[ " ${CODER_PROFILES[*]} " =~ " $CODER_PROFILE " ]]; then
#           break
#         fi
#       done
#       mkdir -p $ZSH_CONFIG_DIR
#       echo "export CODER_PROFILE=$CODER_PROFILE" > $CODER_PROFILE_FILE
#     fi
#   fi
# }




# Used by package installers to install deps (apt or homebrew)
install_dep() {
  for dep in "$@"; do
    command -v $dep &> /dev/null && continue

    if [[ "$(os)" == "linux" ]]; then
      sudo apt install $dep -y
    elif [[ "$(os)" == "macos" ]]; then
      brew install $dep
    fi
  done
}

debug() {
  echo "os: $(os)"
  echo "arch: $(arch)"
  echo "has_ssh_access: $(has_ssh_access && echo "true" || echo "false")"
  echo "coder_profile: ${CODER_PROFILE:-unset}"
}

has_ssh_access() {
  # Check if ssh-agent has loaded keys
  if ssh-add -l &>/dev/null; then
    return 0  # true - agent has keys
  fi

  # Check if id_rsa file exists
  if [[ -f $HOME/.ssh/id_rsa ]]; then
    return 0  # true - id_rsa file exists
  fi

  return 1  # false - neither condition met
}

check_sudo() {
  # Check if user has any sudo privileges without prompting
  if ! sudo -n true 2>/dev/null; then
    return 1
  fi

  # Check if user has sudo ALL privileges
  if sudo -l 2>/dev/null | grep -q "(ALL) ALL"; then
    return 0
  else
    return 1
  fi
}

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

# Parse Git URL to create destination directory
# parse_git_url_to_dir() {
#   local git_url=$1
#   local repo_name
# 
#   # Extract repository name from git URL (e.g., "pcs.infra.git" from "git@github.com:maxcole/pcs.infra.git")
#   repo_name=$(basename "$git_url" .git)
# 
#   # Split on dots and create directory structure (e.g., "pcs.infra" becomes "pcs/infra")
#   echo "$repo_name" | sed 's/\./\//g'
# }

setup_xdg() {
  mkdir -p $HOME/.cache $HOME/.config $HOME/.local $HOME/.local/bin $HOME/.local/share $HOME/.local/state
}

# mise; shared with pcs-bootstrap/controller.sh
# deps_mise() {
#   if [[ "$(os)" == "linux" ]]; then
#     sudo apt install cosign curl gpg -y
#     sudo install -dm 755 /etc/apt/keyrings
#     wget -qO - https://mise.jdx.dev/gpg-key.pub | gpg --dearmor | sudo tee /etc/apt/keyrings/mise-archive-keyring.gpg 1> /dev/null
#     echo "deb [signed-by=/etc/apt/keyrings/mise-archive-keyring.gpg arch=$(arch)] https://mise.jdx.dev/deb stable main" | sudo tee /etc/apt/sources.list.d/mise.list
#     sudo apt update
# 
#     sudo apt install mise -y
#   fi
# }
