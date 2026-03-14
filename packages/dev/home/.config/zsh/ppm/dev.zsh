# ppm-dev.zsh

ppm-setup() {
  local user="$1"
  ppm-user-add "$user" --sudo
  ppm-install "$user"
  ppm-login "$user" --ssh
}


ppm-login() {
  local ssh=false
  local user=""

  for arg in "$@"; do
    if [[ "$arg" == "--ssh" ]]; then
      ssh=true
    else
      user="$arg"
    fi
  done

  local sock_dir

  if $ssh; then
    sock_dir="$(dirname "$SSH_AUTH_SOCK")"
    chmod 711 "$sock_dir"
    chmod 666 "$SSH_AUTH_SOCK"
  fi

  if $ssh; then
    sudo --preserve-env=SSH_AUTH_SOCK -iu "$user"
  else
    sudo -iu "$user"
  fi

  if $ssh; then
    chmod 700 "$sock_dir"
    chmod 600 "$SSH_AUTH_SOCK"
  fi
}


# In case the ppm script is unavailable, e.g. softlink target has moved
# ppm install -c ppm/dev
ppm-install() {
  local user="$1"
  _ppm_run_as "$user" "curl https://raw.githubusercontent.com/maxcole/ppm/refs/heads/main/install.sh | bash"
}

_ppm_run_as() {
  local user="$1"
  shift
  echo "Running as $user: $*"
  sudo -iu "$user" -- bash -c "$*"
  echo "Exit code: $?"
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
