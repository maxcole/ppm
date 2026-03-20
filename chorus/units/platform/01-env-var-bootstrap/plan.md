---
---

# Plan 01 — Environment Variable Bootstrap

## Context — read these files first

- `ppm` — lines 1-45: XDG setup, PPM directory variables, `_resolve_path()`, lib sourcing
- `lib/repo.sh` — `collect_repos()`, `collect_packages()`: where `PPM_DATA_HOME` and `packages` are used
- `lib/meta.sh` — `PPM_INSTALLED_DIR` assignment at top of file
- `docs/adr/001-ppm-as-configurable-engine.md` — architectural context

## Overview

Make the ppm script accept configuration from environment variables with backward-compatible defaults. This is the foundation for all subsequent plans — once the engine reads `PPM_ASSET_DIR` etc. from env, everything downstream can be parameterized.

No behavior change for existing users. When called without env vars, ppm behaves identically to today.

## Implementation

### 1. Modify the ppm script's bootstrap section

Replace the hardcoded directory setup (lines ~15-30) with env-var-aware defaults:

```bash
# Asset configuration — overridable by caller (e.g. psm shell function)
PPM_ASSET_DIR="${PPM_ASSET_DIR:-packages}"
PPM_ASSET_HOOK="${PPM_ASSET_HOOK:-install.sh}"
PPM_ASSET_LABEL="${PPM_ASSET_LABEL:-package}"

# XDG directories
XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"

# PPM directories — overridable for alternate profiles
PPM_CONFIG_HOME="${PPM_CONFIG_HOME:-$XDG_CONFIG_HOME/ppm}"
PPM_DATA_HOME="${PPM_DATA_HOME:-$XDG_DATA_HOME/ppm}"
PPM_CACHE_HOME="${PPM_CACHE_HOME:-$XDG_CACHE_HOME/ppm}"

# Derived paths (not overridable — derived from above)
PPM_SOURCES_FILE="$PPM_CONFIG_HOME/sources.list"
PPM_INSTALLED_DIR="$PPM_DATA_HOME/.installed"
PPM_LIB_DIR="${HOME}/.local/lib/ppm"
BIN_DIR="${HOME}/.local/bin"
```

Key changes from current code:
- `PPM_CONFIG_HOME`, `PPM_DATA_HOME`, `PPM_CACHE_HOME` use `${VAR:-default}` instead of direct assignment
- `PPM_ASSET_DIR`, `PPM_ASSET_HOOK`, `PPM_ASSET_LABEL` are new variables with package defaults
- `PPM_INSTALLED_DIR` moves from `lib/meta.sh` to the main script bootstrap so it derives from `PPM_DATA_HOME`
- `XDG_*` variables use `${VAR:-default}` pattern (current code does direct assignment which clobbers any existing XDG vars)

### 2. Update lib/meta.sh

Remove the `PPM_INSTALLED_DIR` assignment at the top of `meta.sh`. It's now set in the main script bootstrap before libs are sourced. Verify that all references to `PPM_INSTALLED_DIR` in meta.sh still work (they will — the variable is in scope when the lib is sourced).

### 3. Update lib/repo.sh

In `collect_packages()`, replace the hardcoded `packages` directory scan with `$PPM_ASSET_DIR`:

Current:
```bash
for pkg_dir in "$PPM_DATA_HOME/$repo_name/packages"/*/; do
```

New:
```bash
for pkg_dir in "$PPM_DATA_HOME/$repo_name/$PPM_ASSET_DIR"/*/; do
```

Also rename the function from `collect_packages` to `collect_assets`. Add a backward-compatible alias:

```bash
collect_assets() {
  # ... implementation using $PPM_ASSET_DIR ...
}

# Backward compatibility — existing code and package-contributed libs may call this
collect_packages() { collect_assets "$@"; }
```

Update all call sites in the main `ppm` script and other lib files to use `collect_assets`.

### 4. Add backend-specific lib sourcing

After sourcing the shared libs from `lib/*.sh`, add conditional sourcing of backend libs:

```bash
# Source shared libraries
for lib_file in "$PPM_REPO_DIR"/lib/*.sh; do
  [[ -f "$lib_file" ]] && source "$lib_file"
done

# Source backend-specific libraries (e.g. lib/packages/*.sh or lib/services/*.sh)
if [[ -d "$PPM_REPO_DIR/lib/$PPM_ASSET_DIR" ]]; then
  for lib_file in "$PPM_REPO_DIR/lib/$PPM_ASSET_DIR"/*.sh; do
    [[ -f "$lib_file" ]] && source "$lib_file"
  done
fi

# Source package-contributed library extensions
if [[ -d "$PPM_LIB_DIR" ]]; then
  for lib_file in "$PPM_LIB_DIR"/*.sh; do
    [[ -f "$lib_file" ]] && source "$lib_file"
  done
fi
```

Note: `lib/packages/` does not exist yet — that's plan 02. This plan just adds the sourcing mechanism so it's ready.

### 5. Update user-facing messages

Anywhere the main script or libs output the word "package" to the user, replace with `$PPM_ASSET_LABEL`. Scan for:
- `echo` statements with "package" in installer, remover, list, show, etc.
- Error messages ("Package not found", etc.)
- Help text — the help command should use `$PPM_ASSET_LABEL`

Be judicious: internal variable names stay as-is (refactoring variable names is noise). Only user-visible output changes.

## Test Spec

### Default behavior unchanged

```bash
# All of these should produce identical output to before the change:
ppm list
ppm list --installed
ppm show zsh
ppm deps rails
ppm src list
```

### Env vars are respected

```bash
# This should fail gracefully (no sources.list at /tmp/test-config/):
PPM_CONFIG_HOME=/tmp/test-config PPM_DATA_HOME=/tmp/test-data PPM_ASSET_DIR=widgets command ppm list
# Expected: "ERROR: Missing /tmp/test-config/sources.list" or similar

# This should show "widget" in error messages:
PPM_ASSET_LABEL=widget PPM_CONFIG_HOME=/tmp/test-config command ppm list 2>&1 | grep -i widget
```

### XDG vars not clobbered

```bash
# If XDG_DATA_HOME is set, ppm should use it:
XDG_DATA_HOME=/tmp/test-xdg command ppm list 2>&1
# Should reference /tmp/test-xdg/ppm in any error
```

## Verification

- [ ] `ppm` script bootstrap section uses `${VAR:-default}` for all configurable paths
- [ ] `PPM_ASSET_DIR`, `PPM_ASSET_HOOK`, `PPM_ASSET_LABEL` are defined with defaults
- [ ] `PPM_INSTALLED_DIR` is set in main script, removed from `meta.sh`
- [ ] `collect_assets()` exists in `repo.sh` using `$PPM_ASSET_DIR`; `collect_packages()` is an alias
- [ ] Backend lib sourcing block exists (even though `lib/packages/` doesn't exist yet)
- [ ] `ppm list` output is identical to pre-refactor
- [ ] `ppm install zsh` works identically
- [ ] `ppm show zsh` works identically
- [ ] `ppm deps rails` works identically
