# Personal Package Manager

## Quick Start

### MacOS
```bash
curl -fsSL https://raw.githubusercontent.com/maxcole/ppm/refs/heads/main/install.sh | bash
```

### Debian 13
```bash
wget -qO- https://raw.githubusercontent.com/maxcole/ppm/refs/heads/main/install.sh | bash
```

### Fedora
```bash
curl -fsSL https://raw.githubusercontent.com/maxcole/ppm/refs/heads/main/install.sh | bash
```

Run it as your normal user, not root. Open a new shell when complete, then run `ppm list` to see available packages.

## What Gets Installed

The install script:
- Installs Homebrew's prerequisites (Debian: `build-essential procps curl file git`; Fedora: `gcc gcc-c++ make procps-ng curl file git`; macOS: Xcode Command Line Tools)
- Installs Homebrew if the machine doesn't have it, then `stow`, `yq` and `mise` from Homebrew (plus `bash` on macOS)
- Adds GitHub's published SSH host keys to `~/.ssh/known_hosts`
- Installs ppm to `~/.local/bin/ppm` and creates config files in `~/.config/ppm/`
- Runs `ppm src update` and installs any packages you name (none by default)

It asks for your sudo password at most once, and only when prerequisites or Homebrew are missing. Passwordless sudo is not needed, and re-running on a set-up machine doesn't prompt.

## Multiple Users

Homebrew supports one owner per installation, so ppm follows that:

- The first user to run the installer on a machine installs Homebrew and owns it. Only that user installs or upgrades Homebrew packages.
- Other users run the installer too. They use the owner's Homebrew tools without writing to it and don't need sudo. If a base tool is missing, the installer names it and tells them to ask the owner to install it.

## Commands

```bash
ppm list                   # List available packages
ppm install [REPO]         # Installs all packages from a specific repo
ppm install [PACKAGE]      # Install a specific package from all repos
ppm install [REPO/PACKAGE] # Install a specific package from a specific repo
ppm src add [REPO_URL]     # Add a package repository
ppm src ssh [REPO]         # Switch GitHub HTTPS sources and remotes to SSH
ppm src update             # Update (git clone/pull) package repositories
```

The `ppm` shell wrapper reloads your shell config itself after a successful `install`,
`remove` or `src update`, so a new package's aliases and completions are there right away.
To reload by hand: `zsrc` in zsh, `. ~/.bashrc` in bash.

## Default Sources

The `ppm/system` package ships `system.list` with these default sources (in priority order). Your own sources go in `user.list` and take priority over them (see [Customizing](#customizing-your-own-repo)):

1. **[ai-ppm](https://github.com/maxcole/ai-ppm)** - AI packages.

2. **[pdt-ppm](https://github.com/maxcole/pdt-ppm)** - Product Development Toolkit packages.

3. **[pde-ppm](https://github.com/maxcole/pde-ppm)** - Personal Development Environment packages.

4. **[ppm](https://github.com/maxcole/ppm)** - This repository.

See each repo's README for available packages.

## Customizing: Your Own Repo

Run `ppm customize` to start customizing this machine:

```bash
ppm customize
```

This command:
1. Creates a local git repo at `~/.local/share/ppm/user` and registers it as the `user` source (highest priority)
2. Gives it a `system` package holding your `user.list` (the list of your sources), so that list now lives in your repo
3. Stows it: `~/.config/ppm/user.list` becomes a link into the repo

From there:
- Take over any ppm-managed file with `ppm file claim <file>` (claims go to the `user` repo by default)
- Add your own packages under `~/.local/share/ppm/user/packages/`
- Commit your changes in `~/.local/share/ppm/user`

To use your repo on other machines, add a remote and push it, and change the `user` line in `user.list` to its git URL. Then install new machines with `--repo` (see below).

## Good to Know

**Portability**: Push your customization repo (see `ppm customize`) to git and you can port your entire system configuration to a new machine by passing its URL to the install script. It is registered as the `user` source and its `system` package is installed:
```bash
curl -fsSL https://raw.githubusercontent.com/maxcole/ppm/refs/heads/main/install.sh | bash -s -- --repo git@github.com:user/my-ppm
```

You can also specify which packages to install (none by default):
```bash
curl -fsSL https://raw.githubusercontent.com/maxcole/ppm/refs/heads/main/install.sh | bash -s -- --repo git@github.com:user/my-ppm zsh vim tmux
```

Alternatively, set environment variables:
```bash
export PPM_INSTALL_REPO=git@github.com:user/my-ppm
```

```bash
export PPM_INSTALL_PACKAGES="git nvim zsh"
```

```bash
curl -fsSL https://raw.githubusercontent.com/maxcole/ppm/refs/heads/main/install.sh | bash
```

**Precedence**: Repositories are processed in the order they are declared: `user.list` first, then `system.list`. When a file exists in multiple repositories at exactly the same path and name then an identical file exists. In order to avoid conflict the first occurance of the file takes precedence. Any identical files in subsequent repositories will be skipped/ignored. This feature allows personal repositories to override defaults in other repositories.

**Copy your authorized_keys to the remote host:**
```bash
ssh-copy-id user@host
```

## Updates

**Updates**: `ppm src update` pulls every source repo now, skipping repos with uncommitted changes to protect local modifications. Commit or stash to receive updates.

**Update a specific remote**:
```bash
ppm src update <repo>
```

**Automatic updates**: `ppm install` pulls only the repos that haven't been updated in the last `PPM_UPDATE_CACHE_DURATION` seconds (default 24 hours), tracked per repo. Repos it skips for uncommitted changes are listed in one line, `Not updated (uncommitted changes): <repos>`, and checked again on the next install. To hide that line, set `PPM_QUIET_SKIPPED_REPOS=true` in `ppm.conf` (it still shows with `--debug`).


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
ppm src add --top $PPM_INSTALL_REPO user
ppm src update user
ppm install -f user/system
```

You should now have access to all of your personal packages.


## Advanced Installation

### Script Only (skip package install)
```bash
curl -fsSL https://raw.githubusercontent.com/maxcole/ppm/refs/heads/main/install.sh | bash -s -- --script-only
```

### Skip Dependencies

Use `--skip-deps` to skip prerequisites and Homebrew setup if you manage them yourself (ppm still needs `git`, `stow` and `yq` on your PATH):
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

**Debian 13**
```bash
wget -q https://raw.githubusercontent.com/maxcole/ppm/refs/heads/main/install.sh
chmod +x ./install.sh
./install.sh
```

**Fedora**
```bash
curl -fsSLO https://raw.githubusercontent.com/maxcole/ppm/refs/heads/main/install.sh
chmod +x ./install.sh
./install.sh
```

## Development

To contribute to ppm or modify the install process:

```bash
ppm src add git@github.com:maxcole/ppm
ppm src update
ppm install ppm/dev
```

The `dev` package adds `ppm user` for testing installs as a throwaway user:

```bash
ppm user setup testuser    # create user with sudo, run install.sh as them, log in with your ssh agent
ppm user remove testuser   # delete the user and their home directory
```

Run `ppm user` for all subcommands.

It also adds `ppm container` for testing in disposable Debian and Fedora containers (requires podman). Containers test your working tree: your repos are mounted read-only, so edits show up in the container without committing.

```bash
ppm container start debian          # build the image if needed and start ppm-debian
ppm container install debian        # run install.sh as owner (sudo password: owner)
ppm container shell debian other    # log in as the second user, who has no sudo
ppm container snapshot debian brew  # save the state after Homebrew is installed
ppm container reset debian brew     # start over from that snapshot in seconds
ppm container install debian --pushed  # in a fresh container: the installer from GitHub
```

Containers don't replace VMs: they have no systemd services, login sessions or kernel features.
