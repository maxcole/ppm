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

Packages should NOT define a `dependencies()` function — use `package.yml` `depends` instead.

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
- `~/.local/lib/ppm/*.sh` — package-contributed library extensions
- `~/.cache/ppm/` — cache files (brew/ppm update timestamps)

## Source Precedence

Repos in `sources.list` are processed in order. When a package exists in multiple repos, first match wins. This lets personal repos override defaults.

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

```
lib/
  core.sh      # os(), arch(), file utils, install_dep(), debug(), user_message(), ppm_fail()
  update.sh    # update_brew_if_needed(), update_ppm_if_needed()
  repo.sh      # collect_repos(), collect_packages()
  stow.sh      # stow_subdir(), package_links(), force_remove_conflicts()
  meta.sh      # meta_depends(), meta_version(), installed tracking (per-package .yml files)
  graph.sh     # resolve_deps(), find_package_dir(), topo sort (production tier)
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
