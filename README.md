# Personal Package Manager

## Quick Start

### MacOS
```bash
curl -fsSL https://raw.githubusercontent.com/maxcole/ppm/refs/heads/main/install.sh | bash
```

### Debian Linux
```bash
wget -qO- https://raw.githubusercontent.com/maxcole/ppm/refs/heads/main/install.sh | bash
```

Open a new shell when complete, then run `ppm list` to see available packages.

## What Gets Installed

The install script:
- Installs dependencies (Homebrew on MacOS, sudo on Linux)
- Installs ppm to `~/.local/bin/ppm`
- Creates config files in `~/.config/ppm/` (symlinked from your local repo)
- Runs `ppm update` and installs packages (defaults to `zsh`)

## Commands

```bash
ppm list                   # List available packages
ppm install [PACKAGE]      # Install a package from all repos
ppm install [REPO/PACKAGE] # Install a package from a specific repo
ppm add-source [REPO_URL]  # Add a package repository
ppm update                 # Update (git clone/pull) package repositories
```

After installing a package, run `zsrc` to reload zsh configuration.

## Default Sources

The install creates a `sources.list` with three sources (in priority order):

1. **Your user ID** - Local-only source at `~/.local/share/ppm/{user_id}` for personal settings that override other repos. Consider backing this up as a git repo.

2. **[pde-ppm](https://github.com/maxcole/pde-ppm)** - Personal Development Environment packages.

3. **[pdt-ppm](https://github.com/maxcole/pdt-ppm)** - Product Development Toolkit packages.

See each repo's README for available packages.

## Good to Know

**Portability**: Back up your personal repo to git and you can port your entire system configuration to a new machine by passing your repo URL to the install script:
```bash
curl -fsSL https://raw.githubusercontent.com/maxcole/ppm/refs/heads/main/install.sh | bash -s -- --repo git@github.com:user/my-ppm
```

You can also specify which packages to install (defaults to `zsh`):
```bash
curl -fsSL https://raw.githubusercontent.com/maxcole/ppm/refs/heads/main/install.sh | bash -s -- --repo git@github.com:user/my-ppm zsh vim tmux
```

Alternatively, set environment variables:
```bash
export PPM_INSTALL_REPO=git@github.com:user/my-ppm
export PPM_INSTALL_PACKAGES="chorus claude git nvim tmux zsh"
curl -fsSL https://raw.githubusercontent.com/maxcole/ppm/refs/heads/main/install.sh | bash
```

**Precedence**: Repositories are processed in the physical order in which they are declared in `sources.list`. When a file exists in multiple repositories at exactly the same path and name then an identical file exists. In order to avoid conflict the first occurance of the file takes precedence. Any identical files in subsequent repositories will be skipped/ignored. This feature allows personal repositories to override defaults in other repositories.

**Updates**: `ppm update` skips repos with uncommitted changes to protect local modifications. Commit or stash to receive updates.

**Updating ppm itself**:
```bash
ppm update ppm
```

## Recommendation
When installing an existing repo on a new machine and using 1password:
```bash
# Install 1password app, 1passowrd cli, chrome and ghostty
ppm install host op ssh
```

- This  will also configure the ssh agent to use 1password for all host connections
- Then open the 1password app, scan with your phone to authenticate
- You should now have git access at the cli

```bash
# Remove the auto generated user source and add your personal repository
ppm remove-source `whoami`
ppm add-source --top [git@github.com:org/repo]
ppm update
```

- You should now have access to all your packages


## Advanced Installation

### Script Only (skip package install)
```bash
curl -fsSL https://raw.githubusercontent.com/maxcole/ppm/refs/heads/main/install.sh | bash -s -- --script-only
```

### Skip Dependencies

Use `--skip-deps` to skip dependency installation (Homebrew, git, stow, etc.) if you already have them:
```bash
curl -fsSL https://raw.githubusercontent.com/maxcole/ppm/refs/heads/main/install.sh | bash -s -- --skip-deps
```

### Manual Installation

Download and run the script manually:

**MacOS**
```bash
curl -fsSLO https://raw.githubusercontent.com/maxcole/ppm/refs/heads/main/install.sh
chmod +x ./install.sh
./install.sh
```

**Debian Linux**
```bash
wget -q https://raw.githubusercontent.com/maxcole/ppm/refs/heads/main/install.sh
chmod +x ./install.sh
./install.sh
```

## Development

To contribute to ppm or modify the install process:

```bash
ppm add-source git@github.com:maxcole/ppm
ppm update
ppm install ppm/dev
```

This creates a chorus space (defualt is `~/spaces/pde` for developing the ppm script, the pde and pdt packages
