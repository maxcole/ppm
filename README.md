
# Personal Package Manager

## Installation Script - What It Does

- Verifies and installs core dependencies for MacOS (xcode and homebrew) or Debian Linux (sudo)
- Installs script dependencies: curl, git, stow, wget
- Installs the ppm script to $HOME/.local/bin/ppm

## Automated Installation

### MacOS
```bash
curl https://raw.githubusercontent.com/maxcole/ppm/refs/heads/main/install.sh | bash
```

### Debian Linux
```bash
wget -qO- https://raw.githubusercontent.com/maxcole/ppm/refs/heads/main/install.sh | bash
```

### Add Personal Development Environment (PDE) packages
```bash
eval "$(/opt/homebrew/bin/brew shellenv)"
export PATH=$PATH:$HOME/.local/bin
ppm add https://github.com/maxcole/pde-ppm
ppm update
ppm install zsh
# Start a new terminal session (ppm and homebrew will be on the $PATH after restart)
ppm list
ppm install [PACKAGE]
```

## Commands
```bash
ppm add [REPO_URL]    # Add a package repository
ppm update            # Update (git clone/pull) package repositories
ppm update ppm        # Update the ppm script to latest version
ppm list              # List available packages
ppm install [PACKAGE] # Install one or more packages
```

After installing or updating a package run `zsrc` to load new or updated zsh aliases and functions contained in the package

## Manual Installation

### MacOS
```bash
curl -O https://raw.githubusercontent.com/maxcole/ppm/refs/heads/main/install.sh
chmod +x ./install.sh
./install.sh
```

### Linux
```bash
wget https://raw.githubusercontent.com/maxcole/ppm/refs/heads/main/install.sh
chmod +x ./install.sh
./install.sh
```

### PDE packages

Add source (git repo with a packages subdir) to `$HOME/.config/ppm/sources.list`

```bash
echo 'https://github.com/maxcole/pde-ppm' >> $HOME/.config/ppm/sources.list
ppm update
ppm list
ppm install [PACKAGE]
```


## Precedence
If a package has multiple repo sources the first repo to write a specific file takes priority. If a subsequent repo contains the same file it will be ignored
