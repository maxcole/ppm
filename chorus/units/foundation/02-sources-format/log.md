---
status: complete
started_at: "2026-03-16T06:13:30+08:00"
completed_at: "2026-03-16T06:15:30+08:00"
deviations: null
summary: Migrated sources.list parsing to two-column format (URL + alias) with backward compatibility
---

# Execution Log

## What Was Done

- Replaced `REPOS` array with parallel `REPO_URLS` and `REPO_NAMES` arrays in `collect_repos()`
- `collect_repos()` now parses two-column format (URL + optional alias), falling back to `basename` if alias absent
- Updated all consumers in ppm: `update()`, `installer()`, `remover()`, `show()`, `path()` to iterate `REPO_URLS`/`REPO_NAMES` instead of `REPOS`
- Updated `collect_packages()` to use `REPO_NAMES` directly instead of deriving names
- Updated `src add` to accept optional alias argument, writes two-column entries
- Updated `src remove` to match on either URL or alias
- Updated help text for `src` subcommands

## Test Results

- `ppm list` returns correct results with existing single-column sources.list
- `ppm src list` displays current sources
- `bash -n` passes on all files
- No remaining `basename "$repo" .git` derivations in iteration code

## Context Updates

- `sources.list` now supports two-column format: `URL  alias`. Single-column (URL only) is backward-compatible via basename fallback.
- Repository data uses parallel arrays `REPO_URLS` and `REPO_NAMES` instead of a single `REPOS` array.
- The alias determines the directory name under `$PPM_DATA_HOME` where repos are cloned.
- `ppm src add <url> [alias]` writes both columns. `ppm src remove` matches on URL or alias.
