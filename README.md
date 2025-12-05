
# Personal Package Manager

## Installation script

- Installs the ppm script to $HOME/.local/bin/ppm
- Installs the ppm library script to $HOME/.cache/ppm/library.sh
- Verifies and installs core dependencies for MacOS (xcode, homebrew) and Debian Linux (sudo)
- Installs package dependencies for MacOS and Debian Linux (git, curl, stow)

```bash
wget -qO- https://raw.githubusercontent.com/maxcole/ppm/refs/heads/main/install.sh | bash
```

OR install manually

```bash
curl -O https://raw.githubusercontent.com/maxcole/ppm/refs/heads/main/install.sh
chmod +x ./install.sh
./install.sh
```

- TODO: update README with code to use wget to just download the install script


## Usage

- add sources (git repos with a packages subdir) to $HOME/.config/ppm/sources.list

```bash
mkdir $HOME/.config/ppm
echo 'https://github.com/maxcole/ppm-core.git' >> $HOME/.config/ppm/sources.list
$HOME/.local/bin/ppm update
```


### Commands

```bash
ppm install # Install one or more packages
ppm list # List available packages
ppm update # Update, i.e. clone, configured repositories
```

- The ppm script iterates over items in sources.list looking for the requested packages to install

# Manual Dependencies

- sudo priviledges
