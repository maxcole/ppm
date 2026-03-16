# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

PPM (Personal Package Manager) ecosystem — a collection of git repos under `~/.local/share/ppm/` that together manage dotfiles, tool configs, and system setup across machines using GNU Stow + bash hooks.

## Repo Layout

```
~/.local/share/ppm/
  ppm/    ← the tool itself (main script, lib/, bootstrap installer)
  pde/    ← Personal Development Environment packages
  pdt/    ← Product Development Toolkit packages
  rws/    ← Personal overrides (highest priority, if present)
```

Each repo has its own git history. Source priority is defined in `~/.config/ppm/sources.list` (first match wins).

## Key Commands

```bash
ppm install [-c] [-f] [-r] [-s] <pkg...>   # install packages (with dep resolution)
ppm remove <pkg...>                          # remove packages
ppm list [--installed] [filter]              # list packages
ppm show <pkg>                               # show package info
ppm deps <pkg...>                            # show dependency tree
ppm update [repo]                            # pull repos
ppm src add/remove/list                      # manage sources.list
```

Flags: `-c` config-only (stow only, skip hooks), `-f` force (remove conflicts), `-r` reinstall, `-s` skip deps.

## Architecture

- **Main script**: `ppm/ppm` — uses `set -euo pipefail`, bash 3.2 compatible (no associative arrays)
- **Libraries**: `ppm/lib/{core,repo,meta,stow,graph,update}.sh` — sourced at startup
- **Install flow**: resolve deps (graph.sh topo sort) → pre_install hook → stow home/ → OS-specific hook → post_install hook
- **Remove flow**: pre_remove hook → unstow → OS-specific remove → post_remove hook
- **Hooks run in subshells** — `set -e` means the subshell must exit 0 or it kills the parent; use `|| true` guards on optional type checks
- **Stow**: files in `packages/<name>/home/` are symlinked to `$HOME` via GNU Stow

## Package Structure

```
packages/<name>/
  package.yml    # version, author, depends
  install.sh     # hooks: pre_install, install_{linux,macos}, post_install, pre_remove, remove_{linux,macos}, post_remove
  home/          # stowed to $HOME
```

Hook helpers: `install_dep`, `user_message`, `ppm_fail`, `debug`, `install_completion`.

## Config Files

- `~/.config/ppm/sources.list` — repo URLs + aliases (two columns)
- `~/.config/ppm/ppm.conf` / `ppm.local.conf` — config variables
- `~/.local/share/ppm/.installed/<repo>/<pkg>.yml` — install tracking

## Sub-Repo Documentation

- `ppm/CLAUDE.md` — detailed ppm tool architecture, lib structure, all commands
- `pde/CLAUDE.md` — PDE package repo structure
