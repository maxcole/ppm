#!/usr/bin/env bash
#
# PPM Install Script
#
# WHAT THIS SCRIPT DOES:
#   1. Installs Homebrew's prerequisites (Debian: apt packages; macOS: Xcode Command Line Tools),
#      asking for sudo only when something is missing
#   2. Installs Homebrew if the machine has none (this user becomes its owner), or uses the existing
#      installation without writing to it when another user owns it
#   3. Installs ppm's base tools from Homebrew: stow, yq, mise (and bash on macOS)
#   4. Adds GitHub's published SSH host keys to ~/.ssh/known_hosts
#   5. Clones ppm to ~/.local/share/ppm/ppm and links it to ~/.local/bin/ppm
#   6. Seeds ~/.config/ppm/ppm.conf and sources.list as regular files from the user-ppm template
#   7. With --repo: adds your repo and installs its ppm package, which replaces the seeded
#      config files with links into your repo
#   8. Runs 'ppm update' and installs packages (default: zsh)
#
# FILES CREATED:
#   ~/.local/share/ppm/ppm/          cloned ppm repo
#   ~/.local/bin/ppm                 link to the ppm script
#   ~/.config/ppm/ppm.conf           seeded from the template (a link into your repo with --repo)
#   ~/.config/ppm/sources.list       seeded from the template (a link into your repo with --repo)
#   ~/.config/ppm/ppm.local.conf     machine-local settings
#   ~/.local/share/ppm/<repo>/       cloned package repos
#
# EXTERNAL FETCHES:
#   https://github.com/maxcole/ppm.git
#   https://raw.githubusercontent.com/maxcole/user-ppm/...             config templates
#   https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh  only when Homebrew is missing
#
# SUDO USAGE:
#   One password prompt, only to install missing prerequisites or to create the Homebrew prefix.
#   A machine that is already set up needs no sudo. Passwordless sudo is not required.
#
# SUPPORTED PLATFORMS: macOS, Debian 13 (and derivatives that declare ID_LIKE=debian)
#
# OPTIONS:
#   --repo <url>    add your package repo first (or set PPM_INSTALL_REPO)
#   --script-only   only clone ppm and seed config
#   --skip-deps     skip prerequisites and Homebrew setup (you manage them)
#   <package...>    packages to install (or set PPM_INSTALL_PACKAGES; default: zsh)
#
# Everything runs from main() on the last line, so a partially downloaded script does nothing.
#
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

BIN_DIR=$HOME/.local/bin
export PATH="$BIN_DIR:$PATH"

XDG_CONFIG_HOME=$HOME/.config
XDG_DATA_HOME=$HOME/.local/share

PPM_CONFIG_HOME=$XDG_CONFIG_HOME/ppm
PPM_DATA_HOME=$XDG_DATA_HOME/ppm

PPM_REPO_URL=https://github.com/maxcole/ppm.git
PPM_REPO_DIR=$PPM_DATA_HOME/ppm
PPM_USER_URL=https://raw.githubusercontent.com/maxcole/user-ppm/refs/heads/main
PPM_SOURCES_FILE=$PPM_CONFIG_HOME/sources.list

OS_RELEASE=${PPM_OS_RELEASE:-/etc/os-release}
BREW_PREFIXES="/opt/homebrew /home/linuxbrew/.linuxbrew"
DEBIAN_PREREQS="build-essential procps curl file git"

# From https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/githubs-ssh-key-fingerprints
# (verified against api.github.com/meta); written directly instead of trusting ssh-keyscan
GITHUB_KNOWN_HOSTS='github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl
github.com ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBEmKSENjQEezOmxkZMy7opKgwFB9nkt5YRrYMjNuG5N87uRgg6CLrbo5wAdT/y6v0mKV0U2w0WZ2YB/++Tpockg=
github.com ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCj7ndNxQowgcQnjshcLrqPEiiphnt+VTTvDP6mHBL9j1aNUkY4Ue1gvwnGLVlOhGeYrnZaMgRK6+PKCUXaDbC7qtbW8gIkhL7aGCsOr/C56SJMy/BCZfxd1nWzAOxSDPgVsmerOBYfNqltV9/hWCqBywINIR+5dIg6JTJ72pcEpEjcYgXkE2YEFXV1JHnsKgbLWNlhScqb2UmyRkQyytRLtL+38TGxkxCflmO+5Z8CSSNY7GidjMIZ7Q4zMjA2n1nGrlTDkzwDCsw+wqFPGQA179cnfGWOWRVruj16z6XyvxvjJwbz0wQZ75XK5tKSb7FNyeIEs4TT4jk+S4dhPeAUC5y+bDYirYgM4GC7uEnztnZyaVWQ7B381AK4Qdrwt51ZqExKbQpTUNn+EjqoTwvqNj4kqx5QUCI0ThS/YkOxJCXmPUWZbhjpCg56i+2aB6CmK2JGhn57K5mj0MNdBXA4/WnwH6XoPWJzK5Nyu2zB3nAZp+S5hpQs+p1vN1/wsjk='


info() { echo -e "${CYAN}==>${NC} $*"; }
warn() { echo -e "${YELLOW}Warning:${NC} $*" >&2; }
die()  { echo -e "${RED}Error:${NC} $*" >&2; exit 1; }


# macos or linux (value of PPM_GROUP_ID, the per-OS stow subdirectory)
os() {
  if [[ "$OSTYPE" == darwin* ]]; then
    echo "macos"
  elif [[ "$OSTYPE" == linux-gnu* ]]; then
    echo "linux"
  else
    echo "unsupported"
  fi
}


# macos, or the supported distro family from os-release (ID first, then ID_LIKE)
# Keep in sync with lib/platform.sh
platform() {
  if [[ "$OSTYPE" == darwin* ]]; then
    echo "macos"
    return
  fi

  local candidates="" candidate
  [[ -r "$OS_RELEASE" ]] && candidates=$(. "$OS_RELEASE" && echo "${ID:-} ${ID_LIKE:-}")
  for candidate in $candidates; do
    case "$candidate" in
      debian) echo "debian"; return ;;
    esac
  done
  echo "unsupported"
}


# First Homebrew prefix that exists; prints nothing if Homebrew is not installed
# Keep in sync with lib/platform.sh
brew_prefix() {
  local prefix
  for prefix in $BREW_PREFIXES; do
    if [[ -x "$prefix/bin/brew" ]]; then
      echo "$prefix"
      return 0
    fi
  done
  return 0
}


# User that owns a Homebrew installation (the repository dir; on Apple silicon that is the prefix)
brew_owner() {
  local dir="$1/Homebrew"
  [[ -d "$dir" ]] || dir="$1"
  if [[ "$(os)" == "macos" ]]; then
    stat -f %Su "$dir"
  else
    stat -c %U "$dir"
  fi
}


base_formulas() {
  if [[ "$(os)" == "macos" ]]; then
    echo "stow yq mise bash"
  else
    echo "stow yq mise"
  fi
}


# Get sudo credentials once with a normal password prompt; exit with guidance if this user can't
ensure_sudo() {
  local reason="$1"
  command -v sudo >/dev/null 2>&1 || die "sudo is not installed. Ask an admin to $reason, then re-run."
  sudo -n true 2>/dev/null && return 0
  info "sudo is needed to $reason"
  sudo -v || die "This user cannot use sudo. Ask an admin to $reason, then re-run."
}


# Debian packages from the arguments that are not installed
debian_missing() {
  local pkg missing=""
  for pkg in "$@"; do
    [[ "$(dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null)" == "install ok installed" ]] || missing="$missing $pkg"
  done
  echo "${missing# }"
}


setup_prereqs() {
  case "$(platform)" in
    debian)
      local missing
      missing=$(debian_missing $DEBIAN_PREREQS)
      [[ -z "$missing" ]] && return 0
      ensure_sudo "install $missing"
      info "Installing prerequisites: $missing"
      sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq </dev/null
      sudo DEBIAN_FRONTEND=noninteractive apt-get install -y $missing </dev/null
      ;;
    macos)
      # Without Homebrew, its installer installs the Command Line Tools itself
      if [[ -n "$(brew_prefix)" ]] && ! xcode-select -p >/dev/null 2>&1; then
        die "Xcode Command Line Tools are missing. Run: xcode-select --install, then re-run."
      fi
      ;;
  esac
}


# Install Homebrew if needed, load its environment, and make sure the base tools are present.
# Only the owner of the installation installs anything; other users are told what to ask for.
setup_brew() {
  local prefix
  prefix=$(brew_prefix)

  if [[ -z "$prefix" ]]; then
    ensure_sudo "create the Homebrew prefix"
    info "Installing Homebrew; $(id -un) will own it"
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" </dev/null
    prefix=$(brew_prefix)
    [[ -n "$prefix" ]] || die "Homebrew was installed but none of these prefixes exist: $BREW_PREFIXES"
  fi

  eval "$("$prefix/bin/brew" shellenv bash)"

  local formula missing=""
  for formula in $(base_formulas); do
    [[ -e "$prefix/opt/$formula" ]] || missing="$missing $formula"
  done
  missing="${missing# }"
  [[ -z "$missing" ]] && return 0

  local owner
  owner=$(brew_owner "$prefix")
  if [[ "$owner" == "$(id -un)" ]]; then
    info "Installing base tools: $missing"
    brew install $missing </dev/null
  else
    die "Homebrew at $prefix is owned by $owner and is missing: $missing
       Ask $owner to run: brew install $missing"
  fi
}


# Add GitHub's host keys unless known_hosts already has an entry for github.com
setup_known_hosts() {
  local file="$HOME/.ssh/known_hosts"
  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"

  if [[ -f "$file" ]]; then
    if command -v ssh-keygen >/dev/null 2>&1; then
      # -F also matches hashed entries
      ssh-keygen -F github.com -f "$file" >/dev/null 2>&1 && return 0
    elif grep -q '^github\.com ' "$file"; then
      return 0
    fi
    # Don't join our first line onto a last line without a newline
    [[ -s "$file" && -n "$(tail -c1 "$file")" ]] && echo >> "$file"
  fi

  echo "$GITHUB_KNOWN_HOSTS" >> "$file"
  chmod 600 "$file"
}


install_ppm() {
  command -v git >/dev/null 2>&1 || die "git is required"
  mkdir -p "$BIN_DIR" "$PPM_DATA_HOME" "$PPM_CONFIG_HOME"
  if [[ ! -d "$PPM_REPO_DIR" ]]; then
    git clone "$PPM_REPO_URL" "$PPM_REPO_DIR"
  fi
  ln -sfn "$PPM_REPO_DIR/ppm" "$BIN_DIR/ppm"
}


# Seed config as regular files; a repo's ppm package later replaces them with links (install_repo)
install_ppm_configs() {
  local pkg_path=packages/ppm/home/.config/ppm config_file

  for config_file in ppm.conf sources.list; do
    if [[ ! -e "$PPM_CONFIG_HOME/$config_file" ]]; then
      curl -fsSL "$PPM_USER_URL/$pkg_path/$config_file" -o "$PPM_CONFIG_HOME/$config_file"
    fi
  done

  if [[ ! -f "$PPM_CONFIG_HOME/ppm.local.conf" ]]; then
    echo "PPM_GROUP_ID=$(os)" > "$PPM_CONFIG_HOME/ppm.local.conf"
  fi
}


install_repo() {
  local repo_name repo_config
  repo_name=$(basename "$repo_url" .git)

  ppm src add --top "$repo_url"
  ppm update

  if [[ ! -d "$PPM_DATA_HOME/$repo_name/packages/ppm" ]]; then
    warn "$repo_name has no ppm package; ~/.config/ppm keeps the seeded config files"
    return 0
  fi

  # -f replaces the seeded regular files with links into the repo
  ppm install -f "$repo_name/ppm"

  repo_config="$PPM_DATA_HOME/$repo_name/packages/ppm/home/.config/ppm/sources.list"
  if [[ -e "$repo_config" && ! -L "$PPM_SOURCES_FILE" ]]; then
    warn "$PPM_SOURCES_FILE is not a link into $repo_name; edits there won't be saved in your repo"
  fi
}


install_packages() {
  local pkg
  for pkg in "$@"; do
    ppm install "$pkg"
  done
  # stow ppm.zsh
  ppm install ppm/ppm
}


main() {
  local skip_deps=false script_only=false
  repo_url="${PPM_INSTALL_REPO:-}"
  local packages=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --skip-deps) skip_deps=true ;;
      --script-only) script_only=true ;;
      --repo)
        [[ $# -ge 2 ]] || die "--repo requires a URL"
        repo_url="$2"
        shift
        ;;
      -*) die "Unknown option: $1" ;;
      *) packages+=("$1") ;;
    esac
    shift
  done

  echo -e "${CYAN}"
  cat << "EOF"
 ____  ____  __  __
|  _ \|  _ \|  \/  |
| |_) | |_) | |\/| |
|  __/|  __/| |  | |
|_|   |_|   |_|  |_|

EOF
  echo -e "Personal Package Manager${NC}"

  [[ "$(id -u)" -ne 0 ]] || die "Run as your normal user, not root (Homebrew refuses to run as root)"

  if $script_only; then
    install_ppm
    install_ppm_configs
    exit 0
  fi

  [[ "$(platform)" != "unsupported" ]] || die "Unsupported platform. Supported: macOS, Debian 13"

  if [[ ${#packages[@]} -eq 0 && -n "${PPM_INSTALL_PACKAGES:-}" ]]; then
    read -ra packages <<< "$PPM_INSTALL_PACKAGES"
  fi
  [[ ${#packages[@]} -gt 0 ]] || packages=(zsh)

  if $skip_deps; then
    local prefix
    prefix=$(brew_prefix)
    [[ -z "$prefix" ]] || eval "$("$prefix/bin/brew" shellenv bash)"
  else
    setup_prereqs
    setup_brew
  fi

  setup_known_hosts
  install_ppm
  install_ppm_configs
  [[ -z "$repo_url" ]] || install_repo
  ppm update
  install_packages "${packages[@]}"

  echo -e "\n${GREEN}Installation complete!${NC}"
  echo -e "Open a new shell or run: ${CYAN}source ~/.zshrc${NC}"
}

main "$@"
