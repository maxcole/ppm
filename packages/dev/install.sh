# ppm/dev

dependencies() {
  echo "chorus"
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

  # local ppm_script=~/.local/bin/ppm
  # rm -f $ppm_script
  # ln -s "$PWD/ppm/ppm" $ppm_script

  rm repos
  ln -s $XDG_DATA_HOME/ppm repos
  pushd $BIN_DIR > /dev/null
  rm ppm
  ln -s $XDG_DATA_HOME/ppm/ppm/ppm .

  popd > /dev/null
}

install_bases() {
  mkdir -p bases
  pushd bases > /dev/null

  local repos=`hub ls --path obsidian`
  for repo in pde pdt; do
    [[ -L "$repo" ]] && continue
    [[ ! -d "$repos/$repo" ]] && continue
    ln -s "$repos/$repo" .
  done

  popd > /dev/null
}
