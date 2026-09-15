# PPM — Personal Package Manager

## What This Is

PPM is a bash-based personal package manager that combines GNU Stow (symlink-based dotfile management) with bash scripts for installation logic. It manages dotfiles and tool configurations across multiple machines.

## Repository Layout

The PPM ecosystem is multiple git repos, all cloned under `~/.local/share/ppm/`:

```
~/.local/share/ppm/
  ppm/              ← this repo (the tool itself)
  pde-ppm/          ← Personal Development Environment packages
  pdt-ppm/          ← Product Development Toolkit packages
  rjayroach-ppm/    ← Personal overrides (highest priority)
```

This repo (`ppm/`) contains:
- `ppm` — the main script (symlinked to `~/.local/bin/ppm`)
- `lib/` — internal library files sourced by ppm
- `packages/` — meta-packages (dev tooling, ppm's own config)
- `install.sh` — bootstrap installer for new machines
- `chorus/units/` — development plans (Chorus methodology)

## Package Structure

Each package is a directory under `<repo>/packages/<n>/`:

```
packages/<n>/
  package.yml     # metadata: version, author, depends
  install.sh      # optional: pre/post_install hooks, OS-specific install
  home/           # optional: stow target → $HOME
```

### package.yml

```yaml
version: 0.1.0
author: rjayroach
depends:
  - mise
  - ruby
```

- `version` — semver, patch auto-bumped by git hooks (future)
- `author` — package author
- `depends` — list of package names (resolved across repos in source order)
- No `depends` key if package has no dependencies

### install.sh Hooks

```bash
pre_install()      # runs before stow
install_macos()    # OS-specific install (brew)
install_linux()    # OS-specific install (apt)
post_install()     # runs after stow + OS install
pre_remove()       # runs before unstow
remove_macos()     # OS-specific removal
remove_linux()     # OS-specific removal
post_remove()      # runs after unstow
```

Available functions packages can call from their hooks:
- `install_dep <pkg...>` — install system packages via apt (Linux) or brew (macOS)
- `debug "message"` — log debug info (visible with `--debug` flag)
- `user_message "message"` — queue a message for the user (displayed after install completes). Supports `\n` for line breaks. Auto-prefixed with `[repo/package]`.
- `ppm_fail "message"` — signal a non-fatal install failure. Prints to stderr immediately and queues for end-of-run summary. Caller should `return` after calling.

## Key Files

- `~/.config/ppm/sources.list` — repo URLs + aliases (two columns)
- `~/.config/ppm/ppm.conf` — configuration variables
- `~/.config/ppm/ppm.local.conf` — machine-local config (not committed)
- `~/.local/share/ppm/.installed/<repo>/<pkg>.yml` — per-package install tracker (version, timestamp, stowed files)
- `~/.local/lib/ppm/*.sh` — package-contributed library extensions. They can add helpers for hooks (e.g. `pde/ruby`'s `install_gem`) or commands: a function named `foo` becomes `ppm foo` (e.g. `ppm/dev`'s `ppm user`)
- `~/.cache/ppm/` — cache files (brew/ppm update timestamps)

## Source Precedence

Repos in `sources.list` are processed in order. When a package exists in multiple repos, each copy is a layer:

- `ppm install git` installs every `git` package in source order (e.g. `user/git`, then `pde/git`). The layers share one stow ignore list (`PPM_IGNORE_ARGS`), so files stowed by a higher-priority layer are skipped by lower ones. This lets personal repos override individual files.
- `ppm install pde/git` installs only that layer. It hits a stow conflict on files owned by a higher layer; this is intended.

## Homebrew Ownership

Homebrew supports one owner per installation (`/opt/homebrew` on Apple silicon macOS, `/home/linuxbrew/.linuxbrew` on Linux; Intel Macs are not supported). The user who installed it owns it and is the only one who installs, updates or upgrades formulas. Other users on the machine run the tools but never write to the prefix. ppm puts brew on PATH itself (`brew_env`), skips `brew update` for non-owners, and uses `brew_require_owner` to tell a non-owner which command the owner has to run.

## Claiming Files

- `ppm file claim <file...> [--repo REPO] [--package NAME]` copies files into `REPO/NAME/home/` and stows them from there. The default repo is `$PPM_DEFAULT_REPO` (default `user`, settable in `ppm.conf`). The default package has the same name as the owning package. A new package with a different name gets `depends: [<owner>]`.
- `ppm file reset <file...>` deletes the claimed copy, restores the owner's link, and removes the claimant package if it becomes empty.
- Claims are recorded in `~/.local/share/ppm/.installed/claims.yml` (file → claimant, owner). The per-package trackers are updated to match.
- Neither command touches git. Commit the changes in the repo yourself.

## Dependencies

- `yq` (mikefarah/yq) — for YAML parsing of package.yml and tracker files
- `stow` — GNU Stow for symlink management
- `git` — repo cloning and updates

## Development

Plans are in `chorus/units/`. Follow the Chorus methodology:
1. Read the unit `.md` for objectives
2. Read the plan's `plan.md` for implementation spec
3. Implement and test
4. Write `log.md` on completion

### Lib Structure

`ppm` holds only bootstrap: paths, library sourcing, `*.conf` loading, flag parsing and dispatch. Each command lives in the lib file for its area, next to its helpers:

```
lib/
  core.sh        # API for package hooks: os(), arch(), install_dep(), add_to_file(), remove_from_file(),
                 # debug(), user_message(), ppm_fail()
  platform.sh    # platform() (macos/debian), brew_prefix(), brew_env(), brew_owner(), brew_is_owner(),
                 # brew_require_owner(), update_brew_if_needed()
  sources.sh     # src, update, package; collect_repos(), update_ppm_if_needed()
  packages.sh    # list, show, path, deps; collect_packages(), find_package_dirs(), resolve_deps() (layered topo sort),
                 # package.yml reads (meta_depends, meta_version), install trackers (meta_mark_installed, ...)
  installer.sh   # install, remove; install_single_package(), remover(), stow_package(), PPM_IGNORE_ARGS
  file.sh        # file claim|reset (file_command), claims.yml
  completion.sh  # completion
```

Flags (`force`, `config`, `reinstall`, `skip_deps`) are locals of `main()` that commands read through dynamic scoping.

Sourcing order in `ppm`:
1. `$PPM_REPO_DIR/lib/*.sh` (ppm's own libraries)
2. `$PPM_LIB_DIR/*.sh` (package-contributed extensions from `~/.local/lib/ppm/`)

### Testing

No automated test suite. Verification is manual per plan spec. Key commands to validate:
- `ppm list` / `ppm list --installed`
- `ppm install <pkg>` / `ppm remove <pkg>`
- `ppm show <pkg>`
- `ppm deps <pkg>` (dependency tree visualization)
