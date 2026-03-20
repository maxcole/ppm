---
---

# Plan 02 — Sources.list Two-Column Format

## Context — read these files first

- `ppm` — command dispatch and `src()` function
- `lib/repo.sh` — `collect_repos()`, `collect_packages()`, `is_repo_name()` (after plan 01)
- `lib/core.sh` — `is_git_url()` (after plan 01)
- `~/.config/ppm/sources.list` — current single-column format

## Overview

Change `sources.list` from a single-column format (one URL per line) to a two-column format (URL + local alias). The alias determines the directory name under `$PPM_DATA_HOME` where the repo is cloned. This solves naming collisions when two repos share the same basename (e.g., `lgat/ppm.git` and `maxcole/ppm.git`).

Current format:
```
git@github.com:rjayroach/rjayroach-ppm
git@github.com:maxcole/ppm
git@github.com:maxcole/pde-ppm
```

New format:
```
git@github.com:rjayroach/rjayroach-ppm  rjayroach-ppm
git@github.com:maxcole/ppm              ppm
git@github.com:maxcole/pde-ppm          pde-ppm
```

Backward compatibility: if the second column is missing, fall back to `basename "$url" .git` (current behavior).

## Implementation

### 1. Update `collect_repos()` in `lib/repo.sh`

Currently builds `REPOS=()` as a flat array of URLs. Change to build two parallel arrays:

```bash
REPO_URLS=()
REPO_NAMES=()
```

Parse each non-empty, non-comment line: split on whitespace, first field is URL, second field (if present) is the alias. If no second field, derive from `basename "$url" .git`.

### 2. Update all consumers of `REPOS`

Every function that iterates `REPOS` and derives `repo_name` via `basename "$repo" .git` must switch to using the parallel arrays. Affected functions:

In `lib/repo.sh`:
- `collect_packages()` — iterates repos, uses repo_name for package paths
- `is_repo_name()` — checks if a name matches a known repo

In `ppm` (command functions):
- `update()` — clones/pulls repos by name
- `installer()` — walks repos to find packages
- `remover()` — walks repos to unstow packages
- `show()` — walks repos to display package info
- `path()` — walks repos to find package paths
- `package()` — extracts repo_name from URL

The pattern changes from:
```bash
for repo in "${REPOS[@]}"; do
  local repo_name=$(basename "$repo" .git)
  ...
done
```

To:
```bash
for i in "${!REPO_URLS[@]}"; do
  local repo_url="${REPO_URLS[$i]}"
  local repo_name="${REPO_NAMES[$i]}"
  ...
done
```

### 3. Update `src add`

When adding a new source, accept an optional second argument for the alias:
```bash
ppm src add <url> [alias]
```

If alias is not provided, derive from basename. Write both columns to `sources.list`.

### 4. Update `src remove`

Match on either URL or alias when removing.

### 5. Update `expand_packages()`

When checking `is_repo_name`, it already uses the name — just ensure `is_repo_name` checks `REPO_NAMES` array.

### 6. Update completion

The zsh completion function `_ppm_packages_available` currently scans `$PPM_DATA_HOME/*/packages` to discover repos by directory name. This still works since the alias IS the directory name. No change needed.

## Test Spec

Manual verification:
- Convert existing `sources.list` to two-column format
- `ppm list` returns the same results as before
- `ppm install pde-ppm/git` resolves correctly using the alias
- `ppm src add git@github.com:example/test-ppm test-alias` writes both columns
- `ppm src remove test-alias` removes the line
- A single-column line (no alias) still works via basename fallback

## Verification

- [ ] `collect_repos` populates both `REPO_URLS` and `REPO_NAMES`
- [ ] No code remains that derives repo_name via `basename "$repo" .git` (except the fallback in `collect_repos` itself)
- [ ] `ppm src list` displays both URL and alias
- [ ] `ppm install <alias>/package` works
- [ ] `ppm install <package>` (no repo prefix) searches all repos in source order
