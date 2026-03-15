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

Each package is a directory under `<repo>/packages/<name>/`:

```
packages/<name>/
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

Packages should NOT define a `dependencies()` function — use `package.yml` `depends` instead.

## Key Files

- `~/.config/ppm/sources.list` — repo URLs + aliases (two columns)
- `~/.config/ppm/ppm.conf` — configuration variables
- `~/.config/ppm/ppm.local.conf` — machine-local config (not committed)
- `~/.local/share/ppm/.installed.yml` — tracks installed packages
- `~/.local/lib/ppm/*.sh` — package-contributed library extensions
- `~/.cache/ppm/` — cache files (brew/ppm update timestamps)

## Source Precedence

Repos in `sources.list` are processed in order. When a package exists in multiple repos, first match wins. This lets personal repos override defaults.

## Dependencies

- `yq` (mikefarah/yq) — for YAML parsing of package.yml and .installed.yml
- `stow` — GNU Stow for symlink management
- `git` — repo cloning and updates

## Development

Plans are in `chorus/units/`. Follow the Chorus methodology:
1. Read the unit `.md` for objectives
2. Read the plan's `plan.md` for implementation spec
3. Implement and test
4. Write `log.md` on completion

### Lib Structure

```
lib/
  core.sh    # os(), arch(), file utils, debug(), user_message()
  brew.sh    # update_brew_if_needed(), install_dep()
  repo.sh    # collect_repos(), collect_packages(), update_ppm_if_needed()
  stow.sh    # stow_subdir(), package_links(), force_remove_conflicts()
  meta.sh    # meta_depends(), meta_version(), installed tracking
  graph.sh   # resolve_deps(), find_package_dir(), topo sort
```

Sourcing order in `ppm`:
1. `$PPM_REPO_DIR/lib/*.sh` (ppm's own libraries)
2. `$PPM_LIB_DIR/*.sh` (package-contributed extensions from `~/.local/lib/ppm/`)

### Testing

No automated test suite. Verification is manual per plan spec. Key commands to validate:
- `ppm list` / `ppm list --installed`
- `ppm install <pkg>` / `ppm remove <pkg>`
- `ppm show <pkg>`
- `ppm deps <pkg>` (dependency tree visualization)
