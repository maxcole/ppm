# ppm.zsh

# In case the ppm script is unavailable, e.g. softlink target has moved
ppm-fix() {
  rm -f ~/.local/bin/ppm
  curl https://raw.githubusercontent.com/maxcole/ppm/refs/heads/main/install.sh | bash
  ppm install ppm/dev
}
