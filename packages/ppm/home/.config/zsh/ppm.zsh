# ppm.zsh

if ! command -v ppm >/dev/null 2>&1; then
  return
fi

# Wrapper to handle `ppm cd` since subshells can't change parent directory
ppm() {
  if [[ "${1:-}" == "cd" ]]; then
    shift
    local verbose_flag=""
    [[ "${1:-}" == "-v" ]] && { verbose_flag="-v"; shift; }
    if [[ $# -eq 0 ]]; then
      cd "${XDG_DATA_HOME:-$HOME/.local/share}/ppm"
    else
      local pkg_path
      pkg_path=$(command ppm path $verbose_flag "$@") || return $?
      cd "$pkg_path"
    fi
  else
    command ppm "$@"
    local ret=$?
    if [[ $ret -eq 0 && "$1" =~ ^(install|update|remove)$ ]]; then
      zsrc
    fi
    return $ret
  fi
}
