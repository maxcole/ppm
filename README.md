
# Personal Package Manager

## Installation Script - What It Does

- Installs the ppm script to $HOME/.local/bin/ppm
- Verifies and installs core dependencies for MacOS (xcode, homebrew) or Debian Linux (sudo)
- Installs script dependencies: curl, git, stow, wget

## Automated Installations

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
ppm add 'https://github.com/maxcole/pdos-core.git'
ppm update
ppm install zsh
# restart or start a new terminal session (ppm will be on the $PATH after restart)
ppm list
ppm install ruby
```

## Commands
```bash
ppm add REPO_URL # Add a package repository
ppm update # Update, i.e. clone, configured repositories
ppm list # List available packages
ppm install # Install one or more packages
```

## Manual Installations

### MacOS
```bash
curl -O https://raw.githubusercontent.com/maxcole/ppm/refs/heads/main/install.sh
chmod +x ./install.sh
./install.sh
```

### Linux
```bash
# TODO: update README with code to use wget to just download the install script
```

### PDOS packages

- add sources (git repo with a packages subdir) to `$HOME/.config/ppm/sources.list`

```bash
echo 'https://github.com/maxcole/pdos-core.git' >> $HOME/.config/ppm/sources.list
ppm update
```
