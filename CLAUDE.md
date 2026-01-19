# PPM - Personal Package Manager

PPM is a bash-based package manager for managing dotfiles and development environment configurations using GNU Stow for symlink management.

## Directory Structure

```
~/.local/share/ppm/           # PPM_DATA_HOME - cloned repositories
├── ppm/                      # Main ppm repository
│   ├── ppm                   # Main executable script
│   ├── ppm.conf              # Default configuration
│   ├── sources.list          # Default repository sources
│   └── packages/             # Local packages
│       └── dev/              # Development meta-package
└── <repo-name>/              # Cloned repos from sources.list
    └── packages/
        └── <package-name>/

~/.config/ppm/                # PPM_CONFIG_HOME
├── ppm.conf                  # User configuration (sourced as env vars)
└── sources.list              # Git URLs for package repositories

~/.cache/ppm/                 # PPM_CACHE_HOME
└── brew_last_update          # Homebrew update timestamp
```

## Commands

| Command | Description |
|---------|-------------|
| `ppm add <git-url>` | Add a repository URL to sources.list |
| `ppm update` | Clone/pull all repositories from sources.list |
| `ppm update ppm` | Self-update ppm from GitHub |
| `ppm list [filter]` | List available packages, optionally filtered |
| `ppm install [-c] [-f] [repo/]pkg...` | Install packages (-c: config only, -f: force reinstall) |
| `ppm remove [repo/]pkg...` | Remove/uninstall packages |
| `ppm show [repo/]pkg` | Show package dependencies and directory trees |

## Package Structure

```
packages/<name>/
├── install.sh              # Optional: lifecycle hooks
├── home/                   # Files symlinked to $HOME via stow
│   ├── .config/            # → ~/.config/
│   ├── .local/bin/         # → ~/.local/bin/
│   └── .claude/            # → ~/.claude/
└── space/                  # Project workspace contents (requires hub)
```

### home/ Directory

- Uses GNU `stow --no-folding` to create symlinks into `$HOME`
- Files mirror the exact `$HOME` directory structure
- Multiple packages can contribute to the same directory without conflicts
- Example: `packages/nvim/home/.config/nvim/init.lua` → `~/.config/nvim/init.lua`

### space/ Directory

- Optional project-specific workspace contents
- Requires `hub` command (from chorus package) to be installed
- Target path defined by `space_path()` function in install.sh
- Uses `stow -d $package_dir -t $(space_path) space`

## install.sh Lifecycle Hooks

```bash
# Called first - returns space-separated package names
dependencies() {
  echo "dep1 dep2 dep3"
}

# Runs before stow creates symlinks
pre_install() {
  # e.g., backup existing configs
}

# Platform-specific installation (runs after stow)
install_linux() {
  install_dep build-essential libssl-dev
}

install_macos() {
  install_dep openssl
}

# Runs after platform-specific install
post_install() {
  # e.g., run plugin installers
}

# Define where space/ contents are symlinked
space_path() {
  echo "$HOME/spaces/myproject"
}

# Runs after space symlinks are created
space_install() {
  # e.g., clone additional repos
}

# Removal hooks (opposite order)
pre_remove() { }
remove_linux() { }
remove_macos() { }
post_remove() { }
```

## Helper Functions Available in install.sh

| Function | Description |
|----------|-------------|
| `install_dep <packages...>` | Install via apt (Linux) or brew (macOS) |
| `os` | Returns "linux" or "macos" |
| `arch` | Returns "arm64" or "amd64" |

## Package Resolution

When installing `ppm install pkg`:
1. Searches all repos in sources.list order
2. First match wins (priority by order in sources.list)

When installing `ppm install repo/pkg`:
1. Only searches the specified repository
2. Useful when multiple repos have same package name

## Environment Variables

Set in `~/.config/ppm/ppm.conf` (sourced as environment variables):

```bash
HOMEBREW_UPDATE_CACHE_DURATION=86400  # Seconds between brew updates (default: 24h)
```

## XDG Base Directory Compliance

PPM follows the XDG Base Directory Specification:
- `XDG_CONFIG_HOME` (~/.config) - Configuration files
- `XDG_DATA_HOME` (~/.local/share) - Data files (cloned repos)
- `XDG_CACHE_HOME` (~/.cache) - Cache files

## Key Implementation Details

- Uses `set -euo pipefail` for strict error handling
- Command dispatch via `declare -f "$command"` function lookup
- Dependencies installed recursively before parent package
- Stow's `--no-folding` prevents directory folding for home/
- Subshells used when sourcing install.sh to isolate side effects
