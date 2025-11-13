
# XDG directories
XDG_BIN_DIR=$HOME/.local/bin
XDG_CONFIG_DIR=$HOME/.config

# PPM directories and files
PPM_CONFIG_DIR=$XDG_CONFIG_DIR/ppm
PPM_SOURCES_FILE=$PPM_CONFIG_DIR/sources.list


# Install dependencies using the OS specific pacakge manager (apt or homebrew)
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
