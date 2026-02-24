# PPM Development Space

This is a workspace for developing and maintaining PPM (Personal Package Manager) and its ecosystem of package repositories.

## Directory Structure

```
~/spaces/ppm/
├── CLAUDE.md           # This file (symlinked from dev package)
├── .claude/            # Claude configuration (symlinked from dev package)
├── .obsidian/          # Obsidian vault settings for this space
├── repos/              # → ~/.local/share/ppm (all PPM repositories)
│   ├── ppm/            # Main PPM tool and core packages
│   ├── pde-ppm/        # Personal Development Environment packages
│   ├── pdt-ppm/        # Personal Dev Tools packages
│   ├── lgat-ppm/       # LGAT packages
│   ├── pcs-ppm/        # PCS packages
│   ├── rjayroach-ppm/  # rjayroach packages
│   ├── roteoh-ppm/     # roteoh packages
│   └── rws-ppm/        # RWS packages
└── bases/              # Knowledge bases (documentation separate from code)
    ├── pde/            # → iCloud Obsidian vault for PDE docs
    └── pdt/            # → iCloud Obsidian vault for PDT docs
```

## Knowledge Bases (bases/)

The `bases/` directory contains symlinks to Obsidian vaults that hold documentation and project management content separate from the code repositories. This separation allows:

- Documentation to be edited and synced via Obsidian across devices
- Agile boards and project tracking alongside technical docs
- Rich markdown editing with Obsidian plugins
- Clear boundary between code (repos/) and documentation (bases/)

### Base Structure

Each knowledge base typically contains:
- `product/` - Product documentation, specs, and design docs
- `inbox/` - Incoming notes and items to be triaged
- `references/` - Reference materials and external documentation
- `_docs/` - Generated or structured documentation

## Working with Repositories

Each repository in `repos/` is a PPM package repository containing:
- `packages/` - Directory of installable packages
- `README.md` - Repository description

### Package Structure

All packages follow the same pattern:
- `packages/<name>/install.sh` - Main install script with optional `dependencies()` function
- `packages/<name>/home/` - Optional directory for stow (dotfiles, configs)

### Force Removal (`-f` flag)

The `$force` variable (boolean `true`/`false`) is available inside `post_remove()`. Use it to clean up user data and config directories that are normally preserved across reinstalls:

```bash
post_remove() {
  # ... tool uninstall logic ...

  if $force; then
    rm -rf "$XDG_CONFIG_HOME/<tool>"
    rm -rf "$XDG_DATA_HOME/<tool>"
  fi
}
```

By default, `ppm remove` preserves these directories so credentials, config, and working data survive a reinstall. `ppm remove -f` signals the user wants a full teardown.

The main `ppm` repository additionally contains:
- `ppm` - The main executable script
- `ppm.conf` - Default configuration
- `sources.list` - Default repository sources
- `CLAUDE.md` - Detailed PPM documentation (see below)

## PPM Documentation

For detailed information about PPM commands, package structure, and lifecycle hooks, see:
- `repos/ppm/CLAUDE.md` - Complete PPM reference

## Cross-Platform

All packages must work on both macOS and Linux. Avoid platform-specific assumptions:

- Use `mktemp` (not hardcoded `/tmp` paths) — macOS uses a per-user `$TMPDIR` under `/var/folders/`
- Use `command -v` to check for binaries (not `which`)
- Don't assume GNU coreutils flags — stick to POSIX-compatible options or check the platform
- Use `$XDG_CONFIG_HOME`, `$XDG_DATA_HOME`, etc. rather than hardcoded `~/.config` paths
- Test `install.sh` lifecycle hooks on both platforms when possible

## Credential Management (1Password)

Packages that handle credentials should integrate with the `op` CLI (1Password) for secure secret injection. The pattern:

1. **Prefer `op` injection over files on disk.** Use `op read` or `op run` to inject credentials at runtime rather than storing them as local files.
2. **Degrade gracefully.** If `op` is not installed or the credential references aren't configured, fall back to reading from local files. The package must work standalone — `op` is an optional security upgrade, not a hard dependency.
3. **Only fall back to file-based injection when the tool requires it.** Some tools (like GAM) only read credentials from files and don't support env var injection. In those cases, write `op read` output to temp files, pass the paths to the tool, and clean up after. Use `trap ... INT TERM` to ensure cleanup on interruption. Temp files live under `$TMPDIR`/`/tmp` so they're purged on reboot regardless.
4. **Keep credential references configurable.** Define `op://` references as env vars (e.g. `GAM7_OP_OAUTH2`) that the user sets in their shell config. The package checks for their presence to decide whether to use the `op` path.

### Decision flow for new packages

```
Does the tool accept credentials via env vars?
  → Yes: use `op run` to inject directly — no temp files needed
  → No (file-only): use `op read` → temp file → path override → cleanup
```

### Canonical example

- **gam7** (`roteoh-ppm`): File-only tool. Shell wrapper in `gam7.zsh` uses `op read` → `mktemp -d` → `OAUTHFILE`/`OAUTHSERVICEFILE`/`CLIENTSECRETS` path overrides → cleanup on exit/signal.

## Workflow

1. **Code changes**: Work in `repos/<repo-name>/packages/<package>/`
2. **Documentation**: Edit in `bases/<base-name>/` via Obsidian or directly
3. **Testing**: Use `ppm install` and `ppm remove` to test packages
4. **Cross-reference**: Link documentation in bases to code in repos

## Python CLI Tools (mise + pipx)

Python CLI tools should use mise's `pipx:` backend with `uvx = true` instead of manually managing venvs. This gives declarative version pinning, consistent lifecycle management, and simpler install scripts.

### Required Files

1. **Mise config (stowed):** `packages/<tool>/home/.config/mise/conf.d/<tool>.toml`

```toml
[tools."pipx:<tool>"]
version = "latest"   # or pin a specific version
uvx = true
```

2. **Install script:** `packages/<tool>/install.sh`

- `dependencies()` must return `"python"` (ensures python + uv are available via mise)
- `post_install()` activates mise and runs `mise install pipx:<tool>`
- `post_remove()` runs `mise uninstall pipx:<tool>`

### uv Installer Symlink Bug

When using `uvx = true`, installed binaries end up one directory level deeper than mise expects. Each package needs a fix function that creates symlinks from the expected bin path to the actual binary location:

```bash
mise_fix_<tool>() {
  local bin_path=$(mise bin-paths | grep <tool>)
  local tool_bin="${bin_path}/../<tool>/bin"
  ln -sf "${tool_bin}/<binary>" "${bin_path}/<binary>"
}
```

For tools with multiple binaries (like ansible), loop over all commands.

### Canonical Examples

- **ansible** (`pdt-ppm`): Multiple binaries, pinned version, `--include-deps`
- **gam7** (`roteoh-ppm`): Single binary (`gam`), latest version, extra config/work directory setup
