#!/usr/bin/env bash
#
# PPM Install Script
#
# WHAT THIS SCRIPT DOES:
#   1. Sources ppm's libraries, so this bootstrap reuses ppm's own os()/platform()/brew_*
#      helpers instead of copies: from the checkout it runs from, an existing clone, or a
#      download (curl ... | bash)
#   2. Installs Homebrew's prerequisites (Debian: apt, Fedora: dnf packages, including git;
#      macOS: Xcode Command Line Tools), asking for sudo only when something is missing
#   3. Installs Homebrew if the machine has none (this user becomes its owner), or uses
#      the existing installation without writing to it when another user owns it
#   4. Installs ppm's base tools from Homebrew: stow, yq, mise (and bash on macOS) —
#      ppm cannot parse a package.yml (yq) or stow anything until these exist, so they
#      stay an imperative bootstrap and never become tracked ppm dependencies
#   5. Clones ppm to ~/.local/share/ppm/ppm (git is available now) and stows its
#      ppm/system package (the ppm script, its libraries, its default config — ppm.conf and
#      system.list — and ppm's shell integration for sh/zsh/bash) into $HOME, which is what
#      puts ~/.local/bin/ppm on PATH. Files protected with `ppm file protect` are left alone.
#   6. Adds GitHub's published SSH host keys to ~/.ssh/known_hosts
#   7. Seeds an empty ~/.config/ppm/user.list (your repos) and ppm.local.conf (machine-local
#      settings)
#   8. With --repo: adds your customization repo as the "user" source (highest priority) and
#      installs its system package, which replaces the seeded user.list with a link into it
#   9. Runs 'ppm src update', installs any requested packages, then 'ppm install ppm/system'
#      to record ppm itself in the install tracker (no package is installed by default)
#
# FILES CREATED:
#   ~/.local/share/ppm/ppm/          cloned ppm repo (ppm/system package lives inside it)
#   ~/.local/bin/ppm                 link to the ppm script (stowed from ppm/system)
#   ~/.local/lib/ppm/*.sh            ppm's libraries (stowed from ppm/system)
#   ~/.config/{sh,zsh,bash}/ppm.*    ppm's shell integration (stowed from ppm/system)
#   ~/.config/{sh,zsh,bash}/mise.*   mise activation and aliases (stowed from ppm/system)
#   ~/.config/ppm/system.list        default repo list (stowed from ppm/system)
#   ~/.config/ppm/user.list          your repos (a link into your repo with --repo)
#   ~/.config/ppm/ppm.conf           default settings (stowed from ppm/system)
#   ~/.config/ppm/ppm.local.conf     machine-local settings
#   ~/.local/share/ppm/<repo>/       cloned package repos
#
# EXTERNAL FETCHES:
#   https://github.com/maxcole/ppm.git
#   https://raw.githubusercontent.com/maxcole/ppm/...                  ppm's libraries, only when
#                                                                      piped (no checkout to read)
#   https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh  only when Homebrew is missing
#
# SUDO USAGE:
#   One password prompt, only to install missing prerequisites or to create the Homebrew prefix.
#   A machine that is already set up needs no sudo. Passwordless sudo is not required.
#
# SUPPORTED PLATFORMS: macOS, Debian 13 (and derivatives that declare ID_LIKE=debian),
#                      Fedora (and derivatives that declare ID_LIKE=fedora)
#
# OPTIONS:
#   --repo <url>    your customization repo (see `ppm customize`), added as the "user" source
#                   (or set PPM_INSTALL_REPO)
#   --script-only   only clone ppm, stow the system package and seed config (needs stow)
#   --skip-deps     skip prerequisites and Homebrew setup (you manage them)
#   <package...>    packages to install (or set PPM_INSTALL_PACKAGES; none by default)
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
PPM_RAW_URL=https://raw.githubusercontent.com/maxcole/ppm/refs/heads/main
PPM_REPO_DIR=$PPM_DATA_HOME/ppm
PPM_SYSTEM_DIR=$PPM_REPO_DIR/packages/system
PPM_LIB_SUBDIR=packages/system/home/.local/lib/ppm
PPM_INSTALLED_DIR=$PPM_DATA_HOME/.installed   # read by file.sh (protected.yml)

# ppm's libraries this bootstrap reuses: platform/brew helpers, and its own stow (protected files)
PPM_BOOTSTRAP_LIBS="core.sh platform.sh file.sh installer.sh"

# This script's own path; empty when piped (curl ... | bash), a file when run from a checkout
PPM_INSTALLER_PATH="${BASH_SOURCE[0]:-}"
PPM_USER_SOURCES=$PPM_CONFIG_HOME/user.list

# From https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/githubs-ssh-key-fingerprints
# (verified against api.github.com/meta); written directly instead of trusting ssh-keyscan
GITHUB_KNOWN_HOSTS='github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl
github.com ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBEmKSENjQEezOmxkZMy7opKgwFB9nkt5YRrYMjNuG5N87uRgg6CLrbo5wAdT/y6v0mKV0U2w0WZ2YB/++Tpockg=
github.com ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCj7ndNxQowgcQnjshcLrqPEiiphnt+VTTvDP6mHBL9j1aNUkY4Ue1gvwnGLVlOhGeYrnZaMgRK6+PKCUXaDbC7qtbW8gIkhL7aGCsOr/C56SJMy/BCZfxd1nWzAOxSDPgVsmerOBYfNqltV9/hWCqBywINIR+5dIg6JTJ72pcEpEjcYgXkE2YEFXV1JHnsKgbLWNlhScqb2UmyRkQyytRLtL+38TGxkxCflmO+5Z8CSSNY7GidjMIZ7Q4zMjA2n1nGrlTDkzwDCsw+wqFPGQA179cnfGWOWRVruj16z6XyvxvjJwbz0wQZ75XK5tKSb7FNyeIEs4TT4jk+S4dhPeAUC5y+bDYirYgM4GC7uEnztnZyaVWQ7B381AK4Qdrwt51ZqExKbQpTUNn+EjqoTwvqNj4kqx5QUCI0ThS/YkOxJCXmPUWZbhjpCg56i+2aB6CmK2JGhn57K5mj0MNdBXA4/WnwH6XoPWJzK5Nyu2zB3nAZp+S5hpQs+p1vN1/wsjk='


info() { echo -e "${CYAN}==>${NC} $*"; }
warn() { echo -e "${YELLOW}Warning:${NC} $*" >&2; }
die()  { echo -e "${RED}Error:${NC} $*" >&2; exit 1; }


# Clone the ppm repo (which contains the ppm/system package). No linking here — the
# ppm script lands on PATH when ppm/system is stowed (stow_system).
clone_ppm() {
  mkdir -p "$BIN_DIR" "$PPM_DATA_HOME" "$PPM_CONFIG_HOME"
  if [[ ! -d "$PPM_REPO_DIR" ]]; then
    command -v git >/dev/null 2>&1 || die "git is required to clone ppm (drop --skip-deps to install it)"
    git clone "$PPM_REPO_URL" "$PPM_REPO_DIR"
  fi
}


# Download a URL to a file with curl or wget (a fresh machine may have only one)
fetch() {
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$1" -o "$2"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$2" "$1"
  else
    die "curl or wget is required"
  fi
}


# Source ppm's own libraries so this bootstrap reuses os(), platform(), brew_prefix(),
# brew_owner(), brew_env(), system_pkg_*(), brew_missing(), brew_is_owner() instead of
# keeping copies here. This runs before the clone: the prerequisites it installs are what
# provide git. The libraries come from, in order:
#   1. the checkout this script is running from (./install.sh, bash /src/ppm/install.sh)
#   2. an existing clone (a re-run)
#   3. a download from GitHub (curl ... | bash has no checkout)
source_libs() {
  local dir="" tmp f
  [[ -f "$PPM_INSTALLER_PATH" ]] && dir="$(cd "$(dirname "$PPM_INSTALLER_PATH")" && pwd)/$PPM_LIB_SUBDIR"
  [[ -f "$dir/core.sh" ]] || dir="$PPM_REPO_DIR/$PPM_LIB_SUBDIR"

  # installer.sh defines functions named install and remove; install.sh never runs those
  # commands itself, and child processes (the Homebrew installer) don't inherit them
  if [[ -f "$dir/core.sh" ]]; then
    for f in $PPM_BOOTSTRAP_LIBS; do source "$dir/$f"; done
    return
  fi

  tmp=$(mktemp -d)
  for f in $PPM_BOOTSTRAP_LIBS; do
    fetch "$PPM_RAW_URL/$PPM_LIB_SUBDIR/$f" "$tmp/$f" || die "Could not download ppm's $f"
  done
  for f in $PPM_BOOTSTRAP_LIBS; do source "$tmp/$f"; done
  rm -rf "$tmp"   # sourcing has read them
}


# Homebrew base tools that ppm itself needs before it can run
base_formulas() {
  if [[ "$(os)" == "macos" ]]; then
    echo "stow yq mise bash"
  else
    echo "stow yq mise"
  fi
}


# Homebrew's prerequisites per Linux distro family (docs.brew.sh/Homebrew-on-Linux#requirements):
# a compiler toolchain, procps, curl, file and git. For Fedora these are individual packages (the
# equivalents of Debian's build-essential) rather than the development-tools group, so each one
# can be checked with rpm.
linux_prereqs() {
  case "$(platform)" in
    debian) echo "build-essential procps curl file git" ;;
    fedora) echo "gcc gcc-c++ make procps-ng curl file git" ;;
  esac
}


setup_prereqs() {
  case "$(platform)" in
    macos)
      # Without Homebrew, its installer installs the Command Line Tools itself
      if [[ -n "$(brew_prefix)" ]] && ! xcode-select -p >/dev/null 2>&1; then
        die "Xcode Command Line Tools are missing. Run: xcode-select --install, then re-run."
      fi
      ;;
    *)
      local missing
      missing=$(system_pkg_missing $(linux_prereqs) | tr '\n' ' ')
      missing="${missing%% }"; missing="${missing## }"
      [[ -z "$missing" ]] && return 0
      info "Installing prerequisites: $missing"
      system_pkg_install $missing || die "Failed to install prerequisites: $missing"
      ;;
  esac
}


# Install Homebrew if needed, load its environment, and make sure the base tools are present.
# Only the owner of the installation installs anything; other users are told what to ask for.
setup_brew() {
  local prefix
  prefix=$(brew_prefix)

  if [[ -z "$prefix" ]]; then
    _system_sudo "create the Homebrew prefix" || die "sudo is required to install Homebrew"
    info "Installing Homebrew; $(id -un) will own it"
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" </dev/null
    prefix=$(brew_prefix)
    [[ -n "$prefix" ]] || die "Homebrew was installed but none of these prefixes exist: $PPM_BREW_PREFIXES"
  fi

  brew_env

  local missing
  missing=$(brew_missing $(base_formulas) | tr '\n' ' ')
  missing="${missing%% }"; missing="${missing## }"
  [[ -z "$missing" ]] && return 0

  if brew_is_owner; then
    info "Installing base tools: $missing"
    brew install $missing </dev/null
  else
    local owner
    owner=$(brew_owner)
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


# Stow the ppm/system package into $HOME: this is what puts ~/.local/bin/ppm on PATH and
# ~/.local/lib/ppm/*.sh in place, so `ppm` becomes runnable. Idempotent (stow re-links).
# Uses ppm's own stow_package, seeded with the files `ppm file protect` detached, so a re-run
# leaves protected files alone exactly as `ppm install` does.
stow_system() {
  command -v stow >/dev/null 2>&1 || die "stow is required to link ppm (install it or drop --skip-deps)"
  # Clear the stale links among the paths ppm/system ships, derived from the package rather than
  # hardcoded so the list follows whatever it ships. Two kinds are cleared, both of which would
  # otherwise make stow abort the whole run:
  #   - a dangling link, left when a file moved out of ppm/system, or out of a package that is gone
  #     (mise.zsh used to come from pde/mise)
  #   - a link already pointing into ppm/system, i.e. one of ours from an earlier run
  # A live link into any *other* package is left alone: it belongs to a higher-priority layer
  # (user/system's ppm.conf is the documented case), and stow should report that as a real conflict
  # rather than have the bootstrap silently downgrade it. Plain files are never touched, which is
  # how `ppm file protect` and the user's own files survive.
  local rel target
  while IFS= read -r rel; do
    target="$HOME/$rel"
    [[ -L "$target" ]] || continue
    if [[ ! -e "$target" ]] || [[ "$(readlink -f "$target" 2>/dev/null)" == "$PPM_SYSTEM_DIR"/* ]]; then
      rm -f "$target"
    fi
  done < <(package_links "$PPM_SYSTEM_DIR/home")
  local force=false   # read by stow_package; the bootstrap never force-removes
  _reset_ignore_args
  stow_package "$PPM_SYSTEM_DIR"
}


# Seed the machine's own config. ppm.conf and system.list come from stowing ppm/system; here we
# seed an empty user.list the user can add repos to, and machine-local settings. A repo's
# package can later replace user.list with a link into that repo (install_repo).
install_ppm_configs() {
  if [[ ! -e "$PPM_USER_SOURCES" ]]; then
    printf '# Your ppm sources (highest priority). Add with: ppm src add <git-url> [alias]\n' \
      > "$PPM_USER_SOURCES"
  fi

  if [[ ! -f "$PPM_CONFIG_HOME/ppm.local.conf" ]]; then
    echo "PPM_GROUP_ID=$(os)" > "$PPM_CONFIG_HOME/ppm.local.conf"
  fi
}


# --repo: your customization repo (see `ppm customize`), always registered as the "user" source
# (highest priority). Its system package is a layer of ppm/system; installing it with -f swaps the
# seeded user.list for the repo's copy, which lists the repo itself.
install_repo() {
  local alias="$PPM_USER_REPO_ALIAS"
  local pkg_dir="$PPM_DATA_HOME/$alias/packages/system"

  ppm src add --top "$repo_url" "$alias"
  ppm src update "$alias"

  if [[ ! -d "$pkg_dir" ]]; then
    warn "$repo_url has no system package; ~/.config/ppm keeps the seeded config files"
    return 0
  fi

  ppm install -f "$alias/system"

  if [[ -e "$pkg_dir/home/.config/ppm/user.list" && ! -L "$PPM_USER_SOURCES" ]]; then
    warn "$PPM_USER_SOURCES is not a link into your repo; edits there won't be saved in it"
  fi
}


install_packages() {
  local pkg
  for pkg in "$@"; do
    ppm install "$pkg"
  done
  # Record ppm itself in the tracker (and idempotently re-stow the system package)
  ppm install ppm/system
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

  source_libs

  if $script_only; then
    clone_ppm
    brew_env   # put an existing Homebrew (hence stow) on PATH if there is one
    stow_system
    install_ppm_configs
    exit 0
  fi

  [[ "$(platform)" != "unsupported" ]] || die "Unsupported platform. Supported: macOS, Debian 13, Fedora"

  if [[ ${#packages[@]} -eq 0 && -n "${PPM_INSTALL_PACKAGES:-}" ]]; then
    read -ra packages <<< "$PPM_INSTALL_PACKAGES"
  fi

  if $skip_deps; then
    brew_env
  else
    setup_prereqs
    setup_brew
    { command -v yq >/dev/null 2>&1 && command -v stow >/dev/null 2>&1; } ||
      die "ppm needs yq and stow on PATH after setup; check the Homebrew install above"
  fi

  clone_ppm   # after the prerequisites: they are what provide git
  stow_system
  install_ppm_configs
  setup_known_hosts
  [[ -z "$repo_url" ]] || install_repo
  ppm src update || warn "ppm src update skipped one or more repos (uncommitted changes)"
  install_packages ${packages[@]+"${packages[@]}"}

  echo -e "\n${GREEN}Installation complete!${NC}"
  # echo -e "Open a new shell or run: ${CYAN}source ~/.zshrc${NC}"
}

main "$@"
