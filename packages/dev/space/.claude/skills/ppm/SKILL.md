---
description: Core knowledge for PPM (Personal Package Manager) - stow-based dotfile and environment management
globs:
  - "**/ppm/**"
  - "**/.config/ppm/**"
  - "**/packages/*/install.sh"
  - "**/packages/*/home/**"
alwaysApply: false
---

# PPM - Personal Package Manager

## When to Use This Skill

Activate when:
- Working with dotfiles, configs, or environment setup
- User mentions ppm, packages, or stow
- Modifying files under `~/.config/`, `~/.local/`, or `~/.claude/`
- Setting up development tools or shell configurations
- Task involves cross-platform (linux/macos) tooling

## Quick Reference

### Commands
```bash
ppm add <git-url>              # Add package repository
ppm update                     # Clone/pull all repos
ppm update ppm                 # Self-update ppm script
ppm list [filter]              # List packages (optional filter)
ppm install [-c] [-f] <pkg>    # Install (-c=config only, -f=force)
ppm remove <pkg>               # Remove package
```

### Directory Layout
```
~/.config/ppm/sources.list     # Git URLs, one per line
~/.local/share/ppm/
  └── <repo-name>/             # Cloned repos (pde-ppm, lgat-ppm, etc.)
      └── packages/
          └── <package>/
              ├── install.sh   # Optional lifecycle hooks
              ├── home/        # Stowed to $HOME
              └── space/       # Stowed to space_path()
```

### Package Structure
```
packages/<n>/
├── install.sh                 # Optional: bash script with hooks
├── home/                      # Symlinked to $HOME via stow
│   ├── .config/<app>/         # → ~/.config/<app>/
│   ├── .local/bin/            # → ~/.local/bin/
│   └── .claude/               # → ~/.claude/
└── space/                     # For project workspaces
```

### install.sh Hooks (all optional)
```bash
dependencies()    # Echo space-separated package names
pre_install()     # Before stow runs
install_linux()   # Linux-specific installation
install_macos()   # macOS-specific installation  
post_install()    # After stow + install_* complete
pre_remove()      # Before unstow
remove_linux()    # Linux-specific removal
remove_macos()    # macOS-specific removal
post_remove()     # After unstow complete
space_path()      # Return path for space/ stowing
space_install()   # Runs in space_path directory
```

### Available Variables in install.sh
```bash
$BIN_DIR           # ~/.local/bin
$XDG_CACHE_HOME    # ~/.cache
$XDG_CONFIG_HOME   # ~/.config
$XDG_DATA_HOME     # ~/.local/share
```

### Helper Functions
```bash
os()              # Returns "linux" or "macos"
arch()            # Returns "arm64" or "amd64"
install_dep <p>   # Install via apt (linux) or brew (macos)
```

## Multi-Repo System

Roberto's ppm repos by vertical:
- **pde-ppm** - Personal Development Environment (core tools)
- **pdt-ppm** - Personal DevTools
- **ppm** - The ppm script itself + dev package
- **lgat-ppm** - LGAT platform packages
- **pcs-ppm** - PCS infrastructure
- **rjayroach-ppm** - Personal packages
- **roteoh-ppm** - Roteoh project
- **rws-ppm** - RWS project

Priority: First repo in `sources.list` wins for file conflicts.

## Integration Points

### Shell (zsh)
Packages add shell config via: `home/.config/zsh/<n>.zsh`

### Mise (tool versions)
Packages declare tools via: `home/.config/mise/conf.d/<n>.toml`

### Claude Code
Packages add commands via: `home/.claude/commands/<namespace>/`
Packages add docs via: `home/.claude/docs/`
Packages add skills via: `home/.claude/skills/`

### Chorus (project management)
Hubs: `home/.config/chorus/hubs.d/<n>.yml`
Repos: `home/.config/chorus/repos.d/<n>.yml`

### Tmuxinator
Sessions: `home/.config/tmuxinator/<n>.yml`
Nested: `home/.config/tmuxinator/<n>/<variant>.yml`

## Stow Behavior

- Uses `--no-folding`: creates file symlinks, not directory symlinks
- Multiple packages can contribute to same directories
- Idempotent: running again won't duplicate symlinks
- Conflicts resolved by repo priority in sources.list

## Common Operations

### Find what package provides a file
```bash
ls -la ~/.config/nvim/init.lua  # Shows symlink target
```

### See all installed symlinks from a package
```bash
find ~ -maxdepth 4 -type l -ls 2>/dev/null | grep "ppm.*packages/<n>"
```

### Test a package
```bash
ppm install <n>      # Install
ppm remove <n>       # Clean removal
ppm install -f <n>   # Force reinstall
```

### Config-only install (skip scripts)
```bash
ppm install -c <n>   # Only stow home/, skip hooks
```
