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

## Creating Your Personal Package Repo

Use `ppm package` to bootstrap a new personal package repository:

```bash
ppm package git@github.com:user/my-ppm
```

This command:
1. Adds the repo URL to the top of your sources list
2. Clones the repo
3. Populates it with default packages from [user-ppm](https://github.com/maxcole/user-ppm)
4. Copies your current ppm config (sources.list, ppm.conf)
5. Commits the initial packages
6. Installs the ppm package with `-f` to link the config

After running, push your changes:
```bash
cd ~/.local/share/ppm/my-ppm
git push
```

Your personal repo is now the highest priority source, allowing you to customize packages and override defaults from other repos.

## 1Password Integration

If you store your ssh key(s) and other credentials in 1password it is easy to setup:
```bash
ppm install op ssh
```

This command will:
1. Install the 1password desktop app and the 1passowrd cli, and
2. Auto configure the ssh agent to use 1password for all host connections

After running the above command you just need to authorize the cli to access the desktop app:
1. Open 1password desktop
2. For first time setup you can scan the QR with your phone to authenticate
3. Upon login, select 1Password > Settings from the menu bar, then select Developer
4. Select Set Up SSH Agent, then choose whether you want to display SSH key names when you authorize connections
5. Close the window. You do not need to "copy snippet" or have 1password update your ssh config

You should now have access to your credentails, e.g. github, from the cli

## Migrating/Adding a New Host

If you already have a personal ppm repo and you are either:

1. Migrating to a new machine, or
2. Adding an additional machine

Then:

```bash
export PPM_INSTALL_REPO=git@github.com:user/my-ppm
curl -fsSL https://raw.githubusercontent.com/maxcole/ppm/refs/heads/main/install.sh | bash
```

### Missing Personal Repo

If for some reason your repo was not cloned, e.g. it is a private repo and you need ssh credentials from 1password to access it, then:

1. go to 1password section and install it or otherwise get your ssh agent running
2. execute these commands

```bash
export PPM_INSTALL_REPO=git@github.com:user/my-ppm
ppm src add --top $PPM_INSTALL_REPO
ppm update
ppm install -f ppm
```

You should now have access to all of your personal packages.


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
