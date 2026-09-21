# ppm.bash — bash-specific ppm integration (ppm/system).
# The `ppm cd` wrapper is portable and lives in .config/sh/ppm.sh.
# `ppm completion bash` is still a stub, so there is no completion to load yet.

command -v ppm >/dev/null 2>&1 || return

# Called by the ppm() wrapper after a successful install/remove/src update
_ppm_shell_reload() {
  [ -r "$HOME/.bashrc" ] && . "$HOME/.bashrc"
}
