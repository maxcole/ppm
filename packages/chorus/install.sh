# ppm/chorus

space_path() { hub_path ppm; }

space_install() {
  install_repos
  install_bases
}

install_repos() {
  repo_clone ppm/user
  local target_dir="$(hub_path ppm-repos)"
  local repos=$(find $target_dir -maxdepth 1 -mindepth 1 -type d)
  create_symlinks repos $repos
}

install_bases() {
  mkdir -p bases
  local target_dir="$(hub_path obsidian)"
  create_symlinks bases "$target_dir/pde" "$target_dir/pdt"
}

post_install() {
  source <(mise activate bash)
  mise install npm:bats
}
