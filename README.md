
# Personal Package Manager


## Installation script

- Installs the ppm script to $HOME/.local/bin/ppm
- Installs the ppm library script to $HOME/.cache/ppm/library.sh
- Installs dependencies for MacOS and Debian Linux

```bash
wget -qO- https://raw.githubusercontent.com/maxcole/ppm/refs/heads/main/install.sh | bash -s -- all
```

OR install manually

```bash
curl https://raw.githubusercontent.com/maxcole/ppm/refs/heads/main/install.sh
chmod +x ./install.sh
./install.sh
```

- TODO: update README with code to use wget to just download the install script


## Usage

- add sources (git repos with a packages subdir) to $HOME/.config/ppm/sources.list

```bash
mkdir $HOME/.config/ppm
echo 'https://github.com/maxcole/rjayroach-coder.git' >> $HOME/.config/ppm/sources.list
ppm update
```

### List available packages

```bash
ppm list
```


### Install

- The ppm script iterates over items in sources.list looking for the requested packages to install

```bash
ppm install zsh
```


# TODO

# Developing
```bash
mkdir $HOME/.config/ppm
echo 'git@github.com:maxcole/ppm.git' >> $HOME/.config/ppm/sources.list
git clone git@github.com:maxcole/ppm.git $HOME/.cache/ppm
cd $HOME/.local/bin
ln -s $HOME/.cache/ppm/ppm .
```


# Manual Dependencies

- ssh credentials for GH repo access
- sudo priviledges
# sudo echo "ansible ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/ansible

