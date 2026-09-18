# PPM — Personal Package Manager

## What This Is

PPM is a bash-based personal package manager that combines GNU Stow (symlink-based dotfile management) with bash scripts for installation logic. It manages dotfiles and tool configurations across multiple machines.

## Repository Layout

The PPM ecosystem is multiple git repos, all cloned under `~/.local/share/ppm/`:

```
~/.local/share/ppm/          (each directory is named by its source alias)
  ppm/              ← this repo (the tool itself)
  ai/ pdt/ pde/     ← default package repos (system.list)
  user/             ← your customization repo: the "user" source, highest priority
```

This repo (`ppm/`) contains:
- `packages/system/` — ppm *is* a package: the `ppm` script, its libraries and
  `ppm.zsh` live under `packages/system/home/` and are stowed onto the machine like
  any other package (`~/.local/bin/ppm`, `~/.local/lib/ppm/*.sh`, `~/.config/zsh/ppm.zsh`)
- `packages/` — meta-packages (`system` = ppm itself, `dev` = dev/test tooling)
- `install.sh` — bootstrap installer for new machines (clones this repo, installs the
  irreducible prereqs — Homebrew, stow, yq, mise — then stows `ppm/system`)
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

Software a package needs is declared, not installed from hooks:

```yaml
platforms: [macos]          # optional: macos, linux, debian; omit = every platform

brew: [tmux, bat]           # list: every platform
cask: [claude-code]         # Homebrew casks install on Linux too; GUI apps need a map (below)

system:                     # distro package manager
  debian: [nfs-kernel-server]

# a map picks per platform: exact platform first, then "linux" on any distro
brew:
  macos: [podman, podman-compose]
system:
  linux: [podman, podman-compose]
cask:
  macos: [ghostty]          # GUI apps: macOS only
```

- `ppm install` refuses packages whose `platforms` exclude this machine (`ppm install repo/` skips them), then installs what is missing in one batch per manager before any hook runs: system packages (one sudo prompt), brew formulas, casks (on macOS and Linux). Only the Homebrew owner installs brew/cask; other users get the command to ask for.
- A `system` map with entries for other distros but not this one (and no `linux` key) is an error.
- Mise tools: stow `home/.config/mise/conf.d/<tool>.toml`; after stowing, ppm runs `mise install` for the tools named in the resolved packages' toml files.
- Trackers record the formulas/casks ppm installed (`installed_deps`). `ppm remove` uninstalls them when no other installed package recorded or declares them. System packages are never removed.
- `-c` skips all of this, like hooks.

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

Hooks are for imperative work (services, generated config, vendor installers). Software a package needs is declared in `package.yml` (`brew`, `cask`, `system`) and installed by ppm before the hooks run.

Available functions packages can call from their hooks:
- `debug "message"` — log debug info (visible with `--debug` flag)
- `user_message "message"` — queue a message for the user (displayed after install completes). Supports `\n` for line breaks. Auto-prefixed with `[repo/package]`.
- `ppm_fail "message"` — signal a non-fatal install failure. Prints to stderr immediately and queues for end-of-run summary. Caller should `return` after calling.

## Key Files

- `~/.config/ppm/system.list` — default repo list, shipped/stowed by `ppm/system` (ppm-managed; don't edit)
- `~/.config/ppm/user.list` — your repo list (edited by `ppm src`); higher priority than system.list. `sources.list` is the pre-split legacy name, still read as the user list and migrated to `user.list` on the first `ppm src` write
- `~/.config/ppm/ppm.conf` — configuration variables
- `~/.config/ppm/ppm.local.conf` — machine-local config (not committed)
- `~/.local/share/ppm/.installed/<repo>/<pkg>.yml` — per-package install tracker (version, timestamp, stowed files)
- `~/.local/share/ppm/.installed/protected.yml` — files `ppm file protect` detached from ppm; seeded into stow's ignore list so they are never re-linked
- `~/.local/bin/ppm` — the ppm script (stowed from `ppm/system`)
- `~/.local/lib/ppm/*.sh` — ppm's own libraries (stowed from `ppm/system`) plus package-contributed library extensions. Extensions add helpers for hooks (e.g. `pde/ruby`'s `install_gem`) or commands: a function named `foo` becomes `ppm foo` (e.g. `ppm/dev`'s `ppm user`)
- `~/.cache/ppm/` — cache files: `brew_last_update`, and `updated/<alias>` — each repo's last successful clone/pull. `ppm install` auto-updates only the repos older than `PPM_UPDATE_CACHE_DURATION` (default 24h); a repo skipped for uncommitted changes stays stale on its own and is rechecked next time. Install prints one `Not updated (uncommitted changes): <repos>` line for them; `PPM_QUIET_SKIPPED_REPOS=true` in `ppm.conf` moves it to `--debug`

## Source Precedence

Repos come from two lists, read in priority order: `user.list` (yours) first, then
`system.list` (shipped defaults). An alias declared in both is taken from `user.list`.
`ppm src add/remove/ssh` only ever edit `user.list`; `ppm src list` shows both. Within
the merged list, order is priority order. When a package exists in multiple repos, each
copy is a layer:

- `ppm install git` installs every `git` package in source order (e.g. `user/git`, then `pde/git`). The layers share one stow ignore list (`PPM_IGNORE_ARGS`), so files stowed by a higher-priority layer are skipped by lower ones. This lets personal repos override individual files.
- `ppm install pde/git` installs only that layer. It hits a stow conflict on files owned by a higher layer; this is intended.

## Your Customization Repo

The alias `user` (`PPM_USER_REPO_ALIAS` in `core.sh`) is always your own repo:

- `ppm customize` creates it locally: `git init` at `~/.local/share/ppm/user`, a `system` package holding `user.list` (listing the repo itself, as a local path), registered at the top of `user.list`, then `ppm install -f user/system` swaps the plain `user.list` for a link into the repo. It is dispatched through `main()` because it calls `install`.
- Its `system` package is a layer of `ppm/system`, so files it ships (e.g. its own `ppm.conf`) win over ppm's defaults.
- `install.sh --repo <url>` registers that URL as `user` and installs `user/system` with `-f`.
- `ppm file claim` defaults to it.
- Local-path sources are never pulled: after pushing it, set the `user` line in `user.list` to the git URL.

## Homebrew Ownership

Homebrew supports one owner per installation (`/opt/homebrew` on Apple silicon macOS, `/home/linuxbrew/.linuxbrew` on Linux; Intel Macs are not supported). The user who installed it owns it and is the only one who installs, updates or upgrades formulas. Other users on the machine run the tools but never write to the prefix. ppm puts brew on PATH itself (`brew_env`), skips `brew update` for non-owners, and uses `brew_require_owner` to tell a non-owner which command the owner has to run.

## Claiming and Protecting Files

Three levels of ownership for an individual file: ppm owns it (default), *you* own it in
*your repo* (`claim`), or *you* own it locally with ppm detached (`protect`).

- `ppm file claim <file...> [--repo REPO] [--package NAME]` copies files into `REPO/NAME/home/` and stows them from there. The default repo is `$PPM_DEFAULT_REPO` (default `user`, settable in `ppm.conf`). The default package has the same name as the owning package. A new package with a different name gets `depends: [<owner>]`.
- `ppm file reset <file...>` deletes the claimed copy, restores the owner's link, and removes the claimant package if it becomes empty.
- `ppm file protect <file...>` turns a package-managed symlink into a plain local copy (preserving its content) and records it in `protected.yml`. ppm then never re-links or force-removes it — including under `-f` — so you can customize it without a repo. The file is also dropped from its package's tracker.
- `ppm file unprotect <file...>` removes it from `protected.yml`; the next `ppm install -f <package>` re-links it.
- Claims are recorded in `~/.local/share/ppm/.installed/claims.yml` (file → claimant, owner); protections in `~/.local/share/ppm/.installed/protected.yml` (a plain list of `$HOME`-relative paths). The per-package trackers are updated to match.
- None of these touch git. Commit the changes in the repo yourself.

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

ppm is the `ppm/system` package: the `ppm` script and its libraries live under
`packages/system/home/` and are stowed to `~/.local/bin/ppm` and `~/.local/lib/ppm/`.
The `ppm` script holds only bootstrap: paths, library sourcing, `*.conf` loading, flag
parsing and dispatch. Each command lives in the lib file for its area, next to its
helpers:

```
packages/system/home/.local/lib/ppm/
  core.sh        # API for package hooks: os(), arch(), add_to_file(), remove_from_file(),
                 # debug(), user_message(), ppm_fail()
  platform.sh    # platform() (macos/debian), brew_prefix(), brew_env(), brew_owner(), brew_is_owner(),
                 # brew_require_owner(), update_brew_if_needed()
  sources.sh     # src (add, remove, list, ssh, update), customize; collect_repos(), update_ppm_if_needed()
  packages.sh    # list, show, path, deps; collect_packages(), find_package_dirs(), resolve_deps() (layered topo sort),
                 # package.yml reads (meta_depends, meta_version), install trackers (meta_mark_installed, ...)
  installer.sh   # install, remove; install_single_package(), remover(), stow_package(), PPM_IGNORE_ARGS
  file.sh        # file claim|reset|protect|unprotect (file_command), claims.yml, protected.yml
  completion.sh  # completion
```

Flags (`force`, `config`, `reinstall`, `skip_deps`) are locals of `main()` that commands read through dynamic scoping.

Library sourcing in `ppm`: every `*.sh` in `$PPM_LIB_DIR` (`~/.local/lib/ppm/`) is
sourced. That directory holds both ppm's own core libraries (stowed from `ppm/system`)
and package-contributed extensions (e.g. `ppm/dev`'s `container.sh`). During a fresh
install `install.sh` sources the core libs directly from the clone and stows `ppm/system`
so they are present before `ppm` first runs.

### Testing

No automated test suite. Verification is manual per plan spec. Key commands to validate:
- `ppm list` / `ppm list --installed`
- `ppm install <pkg>` / `ppm remove <pkg>`
- `ppm show <pkg>`
- `ppm deps <pkg>` (dependency tree visualization)
