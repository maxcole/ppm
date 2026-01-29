
# PPM - Personal Package Manager

PPM is a cross-platform package manager for managing personal development environments. It uses GNU Stow for symlink-based dotfile management combined with bash scripts for installation logic.

## Architecture Overview

### Directory Structure

PPM follows XDG Base Directory conventions:

```
~/.local/bin/ppm           # The ppm executable itself
~/.config/ppm/
  └── sources.list         # Git repository URLs (one per line)
~/.local/share/ppm/
  └── <repo-name>/         # Cloned repositories
      └── packages/
          └── <package>/   # Individual packages
```

### Core Commands

| Command | Description |
|---------|-------------|
| `ppm add <git-url>` | Add a package repository to sources.list |
| `ppm update` | Clone/pull all repositories in sources.list |
| `ppm update ppm` | Self-update ppm from GitHub |
| `ppm list [filter]` | List available packages (optional substring filter) |
| `ppm install [-c] [-f] <pkg>...` | Install packages (`-c` config-only, `-f` force reinstall) |
| `ppm remove <pkg>...` | Remove packages |

### Helper Functions Available in install.sh

```bash
os()           # Returns "linux" or "macos"
arch()         # Returns "arm64" or "amd64"
install_dep()  # Install system packages via apt (linux) or brew (macos)
```

### XDG Variables Available

```bash
$BIN_DIR         # ~/.local/bin
$XDG_CACHE_HOME      # ~/.cache
$XDG_CONFIG_HOME      # ~/.config
$XDG_DATA_HOME # ~/.local/share
```

## Package Structure

A package lives in `packages/<name>/` within a repository and consists of:

```
packages/<name>/
├── install.sh          # Optional: installation script with lifecycle hooks
├── home/               # Optional: files to symlink into $HOME via stow
│   ├── .config/
│   │   └── <app>/      # Config files → ~/.config/<app>/
│   ├── .local/
│   │   ├── bin/        # Executables → ~/.local/bin/
│   │   └── share/      # Data files → ~/.local/share/
│   └── ...             # Any structure mirroring $HOME
└── space/              # Optional: files for project-specific workspaces
```

### install.sh Lifecycle Hooks

The `install.sh` file is a bash script that can define these functions (all optional):

```bash
# Package dependencies (space-separated package names)
dependencies() {
  echo "dep1 dep2"
}

# Pre-stow setup (runs before symlinks created)
pre_install() {
  # e.g., backup existing configs
}

# OS-specific installation (runs after stow, before post_install)
install_linux() {
  install_dep some-apt-package
  # Download binaries, compile from source, etc.
}

install_macos() {
  install_dep some-brew-package
}

# Post-installation setup
post_install() {
  # e.g., run plugin installers, configure services
}

# Pre-removal cleanup
pre_remove() {
  # e.g., stop services
}

# OS-specific removal
remove_linux() {
  # Uninstall system packages if desired
}

remove_macos() {
  # Uninstall system packages if desired
}

# Post-removal cleanup
post_remove() {
  # e.g., clean up generated files not managed by stow
}

# Project workspace support (optional)
space_path() {
  echo "$HOME/spaces/myproject"  # Where to stow space/ contents
}

space_install() {
  # Runs from within space_path directory
  # e.g., clone repos, initialize project structure
}
```

### Installation Order

1. Dependencies installed recursively
2. `pre_install()` runs
3. `home/` directory stowed to `$HOME` (creates symlinks)
4. `install_linux()` or `install_macos()` runs
5. `post_install()` runs
6. If `space_path()` defined: `space/` stowed to that path, then `space_install()` runs

### The `-c` Flag (Config Only)

When `ppm install -c <pkg>` is used:
- Only the `home/` directory is stowed
- `pre_install`, `install_*`, and `post_install` hooks are skipped
- Useful for applying dotfiles without running installation scripts

### The `-f` Flag (Force)

When `ppm install -f <pkg>` is used:
- Runs `ppm remove` first, then installs fresh

## Package Examples

### Minimal Package (dotfiles only)

```
packages/git/
└── home/
    └── .config/
        └── git/
            ├── config
            └── ignore
```

No `install.sh` needed - stow handles the symlinks.

### Package with Dependencies

```bash
# packages/tmuxinator/install.sh
dependencies() {
  echo "tmux ruby"
}

post_install() {
  source <(mise activate zsh)
  gem install tmuxinator
}
```

### Package with Binary Installation

```bash
# packages/nvim/install.sh
install_linux() {
  command -v nvim &> /dev/null && return
  
  local nvim_arch="x86_64"
  [[ "$(arch)" == "arm64" ]] && nvim_arch="arm64"
  
  curl -L -o "$BIN_DIR/nvim" \
    "https://github.com/neovim/neovim/releases/download/v0.11.4/nvim-linux-${nvim_arch}.appimage"
  chmod +x "$BIN_DIR/nvim"
}

install_macos() {
  install_dep neovim
}

post_install() {
  nvim --headless "+Lazy! sync" +qa
}
```

### Meta-Package (installs all packages in repo)

```bash
# packages/all/install.sh
dependencies() {
  ppm list $(repo_name) | cut -d'/' -f2 | grep -v '^all$'
}

repo_name() {
  basename "$(dirname "$(dirname "$(dirname "${BASH_SOURCE[1]}")")")"
}
```

### Package with Mise Integration

```bash
# packages/claude/install.sh
dependencies() {
  echo "node"
}

post_install() {
  source <(mise activate zsh)
  mise install claude
}
```

## Creating a New Package

1. Create the package directory structure:
   ```bash
   mkdir -p packages/<name>/home/.config/<name>
   ```

2. Add configuration files that should be symlinked into `$HOME`

3. If installation logic is needed, create `install.sh` with appropriate hooks

4. Test installation:
   ```bash
   ppm install <name>
   ```

5. Test removal:
   ```bash
   ppm remove <name>
   ```

## Creating a New Package Repository

1. Create a git repository with this structure:
   ```
   packages/
   └── <package-name>/
       ├── install.sh
       └── home/
   README.md
   ```

2. Add it to ppm:
   ```bash
   ppm add https://github.com/username/my-packages.git
   ppm update
   ppm list
   ```

## Stow Behavior Notes

- Uses `--no-folding` flag: creates individual symlinks for files, not directory symlinks
- Multiple repos can contribute to the same config directories without conflicts
- Files from higher-priority repos (listed first in sources.list) take precedence
- Running stow again is idempotent - won't duplicate symlinks

## Common Patterns

### Shell Integration

Many packages add shell configuration via `home/.config/zsh/<name>.zsh` which gets sourced by the main zsh setup.

### Mise Tool Versions

Packages can declare tool versions via `home/.config/mise/conf.d/<name>.toml`.

### Claude Code Commands

Packages can include Claude Code custom commands via `home/.claude/commands/<namespace>/`.
