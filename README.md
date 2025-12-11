
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

### PDOS packages
```bash
export PATH=$PATH:$HOME/.local/bin
ppm add https://github.com/maxcole/pdos-core
ppm update
ppm install zsh
# Start a new terminal session (ppm will be on the $PATH after restart)
ppm list
ppm install [PACKAGE]
```

## Commands
```bash
ppm add [REPO_URL]    # Add a package repository
ppm update            # Update, i.e. clone, configured repositories
ppm list              # Lists the available packages
ppm install [PACKAGE] # Install one or more packages
```

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

### PDOS packages

Add source (git repo with a packages subdir) to `$HOME/.config/ppm/sources.list`

```bash
echo 'https://github.com/maxcole/pdos-core.git' >> $HOME/.config/ppm/sources.list
ppm update
ppm list
ppm install [PACKAGE]
```
