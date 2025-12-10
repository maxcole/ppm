
# Personal Package Manager

## Installation script

- Installs the ppm script to $HOME/.local/bin/ppm
- Verifies and installs core dependencies for MacOS (xcode, homebrew) and Debian Linux (sudo)
- Installs package dependencies for MacOS and Debian Linux (curl, git, stow, wget)

### Linux
```bash
wget -qO- https://raw.githubusercontent.com/maxcole/ppm/refs/heads/main/install.sh | bash
```

#### Manual Installation
- TODO: update README with code to use wget to just download the install script


### MacOS
```bash
curl https://raw.githubusercontent.com/maxcole/ppm/refs/heads/main/install.sh | bash
```

#### Manual Installation

```bash
curl -O https://raw.githubusercontent.com/maxcole/ppm/refs/heads/main/install.sh
chmod +x ./install.sh
./install.sh
```


## Install PDOS packages

```bash
export PATH=$PATH:$HOME/.local/bin
ppm add 'https://github.com/maxcole/pdos-core.git'
ppm update
ppm install zsh
# restart or start a new terminal session
ppm list
ppm install ruby
```

#### Manual Installation of PDOS packages

- add sources (git repo with a packages subdir) to $HOME/.config/ppm/sources.list

```bash
echo 'https://github.com/maxcole/pdos-core.git' >> $HOME/.config/ppm/sources.list
ppm update
```

### Commands

```bash
ppm add REPO_URL # Add a package repository
ppm install # Install one or more packages
ppm list # List available packages
ppm update # Update, i.e. clone, configured repositories
```

- The ppm script iterates over items in sources.list looking for the requested packages to install

# Manual Dependencies

- linux: sudo priviledges
