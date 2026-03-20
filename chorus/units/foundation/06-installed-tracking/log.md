---
status: complete
started_at: "2026-03-16T08:21:44+08:00"
completed_at: "2026-03-16T08:24:46+08:00"
deviations: "Added passthrough for unknown --flags to commands (e.g., --installed) instead of rejecting them in main()."
summary: Added per-package installed tracking with stale file cleanup, list --installed, and show installed status
---

# Execution Log

## What Was Done

- Added `PPM_INSTALLED_DIR` (`$PPM_DATA_HOME/.installed`) and tracker functions to `lib/meta.sh`:
  - `_tracker_path()` — resolves path to `repo/package.yml` tracker
  - `meta_mark_installed()` — writes tracker with version, timestamp, and stowed file list
  - `meta_installed_files()` — reads file list from tracker
  - `meta_mark_removed()` — deletes tracker and cleans empty parent dir
  - `meta_is_installed()` — checks tracker existence
  - `meta_installed_version()` — reads version from tracker
  - `meta_cleanup_stale()` — removes stale symlinks from previous version, with safety checks
- Updated `installer()` to collect stowed files, run stale cleanup, and write tracker after all phases succeed
- Updated no-installer path in `installer()` to also track stow-only packages
- Updated `remover()` to delete tracker after unstow + post_remove
- Updated `list()` to support `--installed` flag — scans `.installed/` directory for trackers
- Updated `show()` to display installed status (version) and stowed file list
- Modified `main()` flag parsing to pass unknown `--*` flags through to commands instead of rejecting them

## Test Results

- `ppm list` works correctly
- `ppm list --installed` shows installed packages with versions
- `ppm list --installed <filter>` filters results
- `ppm show pde-ppm/git` shows "Status: not installed" or "Status: installed (v0.1.0)" with stowed files
- Tracker files written with correct YAML format (version, installed_at, files)
- `meta_mark_removed` deletes tracker and cleans empty dirs
- All syntax checks pass
- No references to old `.installed.yml` single-file design

## Context Updates

- Installed packages are tracked via per-package YAML files at `$PPM_DATA_HOME/.installed/<repo>/<package>.yml`.
- Tracker files record version, install timestamp, and list of stowed files (relative paths from $HOME).
- On reinstall, `meta_cleanup_stale()` detects files that were in the previous tracker but not the current stow set, and removes them only if they are symlinks pointing into the package directory. Real files and symlinks owned by other repos are left alone.
- `ppm list --installed` scans the `.installed/` directory to show installed packages with versions.
- `ppm show` now displays installed status and stowed file list when a tracker exists.
- `main()` flag parsing passes unknown `--*` flags through to commands, allowing command-specific long flags like `--installed`.
