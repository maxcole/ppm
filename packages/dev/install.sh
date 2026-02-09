# ppm/dev

dependencies() {
  echo "chorus"
}

pre_install() {
  pushd $BIN_DIR > /dev/null
  rm ppm
  ln -s $XDG_DATA_HOME/ppm/ppm/ppm .
  popd > /dev/null
}

space_path() { hub ls --path ppm; }

space_install() {
  install_repos
  install_bases
}

install_repos() {
  repo clone ppm/user
  local target_dir=`hub ls --path ppm-repos`
  local repos=$(find $target_dir -maxdepth 1 -mindepth 1 -type d)
  create_symlinks repos $repos
}

install_bases() {
  mkdir -p bases
  local target_dir=`hub ls --path obsidian`
  create_symlinks bases "$target_dir/pde" "$target_dir/pdt"
}

post_install() {
  source <(mise activate bash)
  mise install npm:bats
}
