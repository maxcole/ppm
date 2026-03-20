---
status: complete
started_at: "2026-03-20T22:16:10+08:00"
completed_at: "2026-03-20T22:21:52+08:00"
deviations: "Plan used ${VAR^} for capitalizing asset label in messages, but bash 3.2 doesn't support case modification. Used $PPM_ASSET_LABEL as-is (lowercase) instead. Also updated lib/graph.sh and lib/meta.sh to use $PPM_ASSET_DIR and $PPM_ASSET_HOOK — plan only mentioned repo.sh and the main script but graph.sh had a hardcoded 'packages' path and meta.sh had hardcoded 'install.sh'."
summary: Made ppm engine configurable via environment variables with backward-compatible defaults
---

# Execution Log

## What Was Done

- Replaced hardcoded directory assignments in ppm bootstrap with `${VAR:-default}` pattern for all configurable paths
- Added three new env vars: `PPM_ASSET_DIR` (default: packages), `PPM_ASSET_HOOK` (default: install.sh), `PPM_ASSET_LABEL` (default: package)
- XDG vars now use `${VAR:-default}` instead of clobbering existing values
- Moved `PPM_INSTALLED_DIR` from `lib/meta.sh` to main script bootstrap (derives from `PPM_DATA_HOME`)
- Renamed `collect_packages()` to `collect_assets()` in `lib/repo.sh`, added backward-compat alias
- Updated all call sites: `ppm` (list), `repo.sh` (expand_packages)
- Replaced hardcoded `packages` path in `lib/graph.sh` `find_package_dir()` with `$PPM_ASSET_DIR`
- Replaced hardcoded `install.sh` in `install_single_package()`, `remover()`, and `lib/meta.sh` with `$PPM_ASSET_HOOK`
- Updated `is_repo_name()` to use `$PPM_ASSET_DIR`
- Added backend-specific lib sourcing: `lib/$PPM_ASSET_DIR/*.sh` sourced after shared libs
- Updated all user-facing messages to use `$PPM_ASSET_LABEL` instead of hardcoded "package"

## Test Results

- `ppm list` → identical output ✓
- `ppm show zsh` → works, label is lowercase "package:" ✓
- `ppm deps rails` → "Install order (4 packages):" ✓
- `ppm install -s zsh` → works ✓
- `ppm list --installed` → works ✓
- `PPM_CONFIG_HOME=/tmp/test-config ./ppm list` → "ERROR: Missing /tmp/test-config/sources.list" ✓
- `PPM_ASSET_LABEL=widget ./ppm show nonexistent` → "Error: widget 'nonexistent' not found" ✓
- `XDG_DATA_HOME=/tmp/test-xdg ./ppm list` → uses custom XDG path ✓

## Notes

Pre-existing bug found: `src list` shows "missing" for all repos when `sources.list` uses single-column format (no alias). The `${line##* }` extraction doesn't fall back to `basename` like `collect_repos` does. Not addressed in this plan.

The `show` command output changed from "Package:" to "package:" due to bash 3.2 not supporting `${VAR^}` case modification. This is a minor cosmetic difference.

## Context Updates

- The ppm engine is now configurable via environment variables: `PPM_CONFIG_HOME`, `PPM_DATA_HOME`, `PPM_CACHE_HOME`, `PPM_ASSET_DIR`, `PPM_ASSET_HOOK`, `PPM_ASSET_LABEL`.
- All variables have backward-compatible defaults matching current ppm behavior.
- `collect_assets()` replaces `collect_packages()` as the primary function; `collect_packages()` remains as an alias.
- Backend-specific libraries are sourced from `lib/$PPM_ASSET_DIR/` when that directory exists (e.g., `lib/packages/`, `lib/services/`).
- `PPM_INSTALLED_DIR` is now derived from `PPM_DATA_HOME` in the main script bootstrap, not in `lib/meta.sh`.
- XDG variables are no longer clobbered — existing values are respected via `${VAR:-default}`.
- All hardcoded `packages` paths and `install.sh` references replaced with `$PPM_ASSET_DIR` and `$PPM_ASSET_HOOK`.
