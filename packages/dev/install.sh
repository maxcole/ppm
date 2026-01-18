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
  # mkdir -p repos
  # pushd repos > /dev/null

  # local repos=`hub ls --path ppm-repos`
  # for repo in ppm pde-ppm pdt-ppm; do
  #   [[ -L "$repo" ]] && continue
  #   [[ ! -d "$repos/$repo" ]] && continue
  #   ln -s "$repos/$repo" .
  # done

  rm -f repos
  ln -s $XDG_DATA_HOME/ppm repos
}

install_bases() {
  mkdir -p bases
  pushd bases > /dev/null

  local bases_dir=`hub ls --path obsidian`
  for base in pde pdt; do
    [[ -L "$base" ]] && continue
    [[ ! -d "$bases_dir/$base" ]] && continue
    ln -s "$bases_dir/$base" .
  done

  popd > /dev/null
}
