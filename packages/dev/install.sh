# ppm/dev

dependencies() {
  echo "chorus"
}

# Removes the ~/.local/bin/ppm script and symlinks it to the repo
# so changes made in the script are carried over to the repo
post_install() {
  pushd $BIN_DIR > /dev/null
  rm ppm
  ln -s $XDG_DATA_HOME/ppm/ppm/ppm .
  popd > /dev/null
}
