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
- Creates default config and sources.list
- Runs `ppm update` and `ppm install zsh`

## Commands

```bash
ppm list                   # List available packages
ppm install [PACKAGE]      # Install a package from all repos
ppm install [REPO/PACKAGE] # Install a package from a specific repo
ppm add [REPO_URL]         # Add a package repository
ppm update                 # Update (git clone/pull) package repositories
```

After installing a package, run `zsrc` to reload zsh configuration.

## Default Sources

The install creates a `sources.list` with three sources (in priority order):

1. **Your user ID** - Local-only source at `~/.local/share/ppm/{user_id}` for personal settings that override other repos. Consider backing this up as a git repo.

2. **[pde-ppm](https://github.com/maxcole/pde-ppm)** - Personal Development Environment packages.

3. **[pdt-ppm](https://github.com/maxcole/pdt-ppm)** - Personal Development Tools packages.

See each repo's README for available packages.

## Good to Know

**Portability**: Back up your personal repo to git and you can port your entire system configuration to a new machine by passing your repo URL to the install script:
```bash
curl -fsSL https://raw.githubusercontent.com/maxcole/ppm/refs/heads/main/install.sh | bash -s -- git@github.com:user/my-ppm
```

**Precedence**: When a package exists in multiple repos, the first repo in sources.list wins. Files already written by a higher-priority repo are skipped.

**Updates**: `ppm update` skips repos with uncommitted changes to protect local modifications. Commit or stash to receive updates.

**Updating ppm itself**:
```bash
ppm update ppm
```

## Advanced Installation

### Script Only (skip zsh install)
```bash
curl -fsSL https://raw.githubusercontent.com/maxcole/ppm/refs/heads/main/install.sh | bash -s -- --script-only
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
ppm add git@github.com:maxcole/ppm
ppm update
ppm install ppm/dev
```
