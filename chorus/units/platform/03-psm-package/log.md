---
status: complete
started_at: "2026-03-20T22:31:26+08:00"
completed_at: "2026-03-20T22:33:41+08:00"
deviations: "Fixed bash 3.2 empty array expansion issues in collect_assets() and list() — used ${ARR[@]+\"${ARR[@]}\"} pattern to guard against unbound variable errors when no repos or packages exist. Pre-existing bug in src list (doesn't skip comment lines) not addressed."
summary: Created psm package with zsh shell function and install hook that bootstraps PSM config/data directories
---

# Execution Log

## What Was Done

- Created `packages/psm/package.yml` with version 0.1.0, depends on ppm
- Created `packages/psm/home/.config/zsh/psm/psm.zsh` with `psm()` shell function that sets PSM env vars and delegates to ppm engine
- Created `packages/psm/install.sh` with `post_install()` that creates `~/.config/psm/` and default `sources.list`
- Fixed bash 3.2 empty array expansion in `lib/repo.sh` `collect_assets()` — `REPO_NAMES` and `filter_repos` now use `${ARR[@]+"${ARR[@]}"}` pattern
- Fixed bash 3.2 empty array expansion in `ppm` `list()` — `PACKAGES` array uses same guard pattern
- These fixes enable clean operation when sources.list has no repo entries (comment-only), as with a fresh PSM install

## Test Results

- `ppm install psm` → resolves ppm dep, installs both, stows psm.zsh, creates config/data dirs ✓
- `psm list` (via env vars) → empty output, no errors ✓
- `psm list --installed` → "No services installed" with correct label ✓
- `psm update` → no repos, no errors ✓
- `psm src list` → runs (shows comments as entries — pre-existing src list bug) ✓
- `ppm list` → still works ✓
- `ppm install zsh` → still works ✓
- `~/.config/psm/sources.list` created ✓
- `~/.local/share/psm/` created ✓
- `~/.config/zsh/psm/psm.zsh` symlinked ✓

## Notes

The `src list` command doesn't skip comment lines from sources.list. This is a pre-existing bug — `src` bypasses `main()` and has its own `while read` loop that doesn't filter comments. Not in scope for this plan.

## Context Updates

- `packages/psm/` is a ppm-managed package that installs the PSM entry point.
- `psm()` zsh shell function sets `PPM_CONFIG_HOME=~/.config/psm`, `PPM_DATA_HOME=~/.local/share/psm`, `PPM_ASSET_DIR=services`, `PPM_ASSET_HOOK=service.sh`, `PPM_ASSET_LABEL=service` and calls `command ppm`.
- PSM and PPM have fully separate config and data directories.
- `ppm install psm` bootstraps PSM config dir with a comment-only `sources.list`.
- Empty array expansion throughout `lib/repo.sh` and `ppm` `list()` now uses bash 3.2-safe `${ARR[@]+"${ARR[@]}"}` pattern.
