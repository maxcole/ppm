# ppm-dev.zsh

# In case the ppm script is unavailable, e.g. softlink target has moved
ppm-fix() {
  rm -f $BIN_DIR/ppm
  curl https://raw.githubusercontent.com/maxcole/ppm/refs/heads/main/install.sh | bash
  ppm install -c ppm/dev
}

# Internal helper: setup passwordless sudo for user
_ppm_user_sudo() {
  local userid="$1"
  local sudoers_file

  if [[ "$(os)" == "macos" ]]; then
    sudoers_file="/private/etc/sudoers.d/$userid"
    sudo dscl . -append /Groups/admin GroupMembership "$userid"
  elif [[ "$(os)" == "linux" ]]; then
    sudoers_file="/etc/sudoers.d/$userid"
  else
    echo "Unsupported OS"
    return 1
  fi

  echo "$userid ALL=(ALL) NOPASSWD:ALL" | sudo tee "$sudoers_file" > /dev/null
  sudo chmod 440 "$sudoers_file"

  if ! sudo visudo -cf "$sudoers_file" &>/dev/null; then
    echo "Error: Invalid sudoers file, removing"
    sudo rm -f "$sudoers_file"
    return 1
  fi

  echo "Configured sudo for user '$userid'"
}

# Create a test user
# Usage: ppm-user-add <userid> [--sudo]
ppm-user-add() {
  local userid="$1"
  local with_sudo=false

  shift 2>/dev/null
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --sudo) with_sudo=true ;;
      *) echo "Unknown option: $1"; return 1 ;;
    esac
    shift
  done

  if [[ -z "$userid" ]]; then
    echo "Usage: ppm-user-add <userid> [--sudo]"
    return 1
  fi

  if id "$userid" &>/dev/null; then
    echo "User '$userid' already exists"
    return 1
  fi

  if [[ "$(os)" == "macos" ]]; then
    sudo sysadminctl -addUser "$userid" -fullName "$userid" -shell /bin/zsh -password ""
  elif [[ "$(os)" == "linux" ]]; then
    sudo useradd -m -s /bin/bash "$userid"
  else
    echo "Unsupported OS"
    return 1
  fi

  if ! id "$userid" &>/dev/null; then
    echo "Failed to create user '$userid'"
    return 1
  fi

  echo "Created user '$userid'"

  [[ "$with_sudo" == true ]] && _ppm_user_sudo "$userid"
}

# Remove a test user
# Usage: ppm-user-remove <userid>
ppm-user-remove() {
  local userid="$1"
  local uid

  if [[ -z "$userid" ]]; then
    echo "Usage: ppm-user-remove <userid>"
    return 1
  fi

  if ! id "$userid" &>/dev/null; then
    echo "User '$userid' does not exist"
    return 1
  fi

  # Safety: prevent removal of system users
  uid=$(id -u "$userid")
  if [[ "$(os)" == "macos" && "$uid" -lt 501 ]] || [[ "$(os)" == "linux" && "$uid" -lt 1000 ]]; then
    echo "Refusing to remove system user '$userid' (UID $uid)"
    return 1
  fi

  # Remove sudoers file first
  if [[ "$(os)" == "macos" ]]; then
    [[ -f "/private/etc/sudoers.d/$userid" ]] && sudo rm -f "/private/etc/sudoers.d/$userid"
    sudo sysadminctl -deleteUser "$userid"
    [[ -d "/Users/$userid" ]] && sudo rm -rf "/Users/$userid"
  elif [[ "$(os)" == "linux" ]]; then
    [[ -f "/etc/sudoers.d/$userid" ]] && sudo rm -f "/etc/sudoers.d/$userid"
    sudo userdel -r "$userid"
  else
    echo "Unsupported OS"
    return 1
  fi

  echo "Removed user '$userid'"
}
