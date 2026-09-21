# ppm.zsh — zsh-specific ppm integration (ppm/system).
# The `ppm cd` wrapper is portable and lives in .config/sh/ppm.sh.
# zcomp and zsrc come from pde/zsh; ppm doesn't depend on that package.

command -v ppm >/dev/null 2>&1 || return

(( $+functions[zcomp] )) && zcomp ppm

# Called by the ppm() wrapper after a successful install/remove/src update
_ppm_shell_reload() {
  (( $+functions[zsrc] )) && zsrc
  (( $+functions[compinit] )) && compinit
}
