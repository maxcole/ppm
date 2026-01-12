# ppm/dev

# dependencies() {
#   echo "chorus"
# }

space_path() { hub ls --path ppm-dev; }

space_install() {
  mkdir -p repos
  pushd repos > /dev/null

  local repos=`hub ls --path ppm-repos`
  for repo in ppm pde-ppm pdt-ppm; do
    [[ -L $repo ]] && continue
    [[ ! -d $repos/$repo ]] && continue
    ln -s $repos/$repo .
  done

  local ppm_script=~/.local/bin/ppm
  if [[ -f "$ppm_script" && ! -L "$ppm_script" ]]; then
    rm $ppm_script
    ln -s "$PWD/ppm/ppm" $ppm_script
  fi

  popd > /dev/null
}
