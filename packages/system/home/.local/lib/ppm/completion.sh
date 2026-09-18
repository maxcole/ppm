#!/usr/bin/env bash
# Shell completion: the completion command

# Output shell completion for zsh or bash
completion() {
  local shell="${1:-zsh}"

  case "$shell" in
    zsh)
      cat <<'EOF'
#compdef ppm

_ppm() {
    local -a subcommands
    local state

    subcommands=(
        'src:Manage source repositories (add, remove, list, ssh, update)'
        'list:List available packages'
        'ls:List available packages (alias for list)'
        'install:Install one or more packages'
        'remove:Remove one or more packages'
        'show:Show package information'
        'path:Output path to a package directory'
        'cd:Change to a package directory'
        'completion:Output shell completion'
        'customize:Create your own "user" repo to customize ppm'
        'file:Claim files into your repo or reset them'
    )

    _arguments -C \
        '1: :->command' \
        '*: :->args'

    case $state in
        command)
            _describe 'command' subcommands
            ;;
        args)
            case ${words[2]} in
                src)
                    if [[ ${#words[@]} -eq 3 ]]; then
                        local -a src_cmds
                        src_cmds=('add:Add a source repository' 'remove:Remove a source repository' 'list:List configured sources' 'ssh:Switch GitHub HTTPS sources to SSH' 'update:Clone and pull source repositories')
                        _describe 'subcommand' src_cmds
                    fi
                    ;;
                install|remove|show|path|cd)
                    _ppm_packages_available
                    ;;
                file)
                    if [[ ${#words[@]} -eq 3 ]]; then
                        local -a file_cmds
                        file_cmds=('claim:Copy files into your repo and stow them' 'reset:Restore the original package links')
                        _describe 'subcommand' file_cmds
                    elif [[ ${words[3]} == reset ]]; then
                        local -a claimed
                        local claims="${XDG_DATA_HOME:-$HOME/.local/share}/ppm/.installed/claims.yml"
                        [[ -f "$claims" ]] && claimed=(${(f)"$(yq -r 'keys[]' "$claims" 2>/dev/null)"})
                        compadd -P "$HOME/" -a claimed
                    else
                        _files
                    fi
                    ;;
                completion)
                    local -a shells
                    shells=('zsh' 'bash')
                    _describe 'shell' shells
                    ;;
            esac
            ;;
    esac
}

_ppm_packages_available() {
    local -a packages
    local ppm_data_home="${XDG_DATA_HOME:-$HOME/.local/share}/ppm"

    if [[ -d "$ppm_data_home" ]]; then
        for repo_dir in "$ppm_data_home"/*/packages; do
            [[ -d "$repo_dir" ]] || continue
            local repo_name="${repo_dir%/packages}"
            repo_name="${repo_name##*/}"
            for pkg_dir in "$repo_dir"/*/; do
                [[ -d "$pkg_dir" ]] || continue
                local pkg_name="${pkg_dir%/}"
                pkg_name="${pkg_name##*/}"
                packages+=("${repo_name}/${pkg_name}")
            done
        done
    fi

    _describe 'package' packages
}

compdef _ppm ppm
EOF
      ;;
    bash)
      echo "# Bash completion not yet implemented"
      ;;
    *)
      echo "Error: Unknown shell '$shell'. Supported: zsh, bash" >&2
      return 1
      ;;
  esac
}
