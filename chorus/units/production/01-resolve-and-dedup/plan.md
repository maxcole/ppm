---
---

# Plan 01 — Dependency Resolution & Deduplication

## Context — read these files first

- `ppm` — `installer()` function, `install()` entry point
- `lib/meta.sh` — `resolve_package_deps()`, `meta_depends()` (from foundation plan 05)
- `lib/repo.sh` — `collect_repos()`, repo precedence logic (foundation plan 02 format)

## Overview

Add `lib/graph.sh` with a `resolve_deps()` function that, given a list of requested packages, recursively walks the `depends` field from `package.yml` across all repos, deduplicates, and returns a flat list of every package that needs to be installed.

This plan does NOT change the install order or rewrite `installer()` — that's plan 02. This plan builds and tests the resolution logic independently.

## Implementation

### 1. Create `lib/graph.sh`

#### `find_package_dir()`

Given a package name (possibly with repo prefix), find its directory on disk. Respects repo precedence from sources.list:

```bash
# Find the package directory for a given package specifier
# Handles both "repo/pkg" and "pkg" (search all repos in order)
# Prints the full path to the package dir and sets FOUND_REPO_NAME
# Usage: find_package_dir <package_spec>
find_package_dir() {
  local pkg="$1"
  local package_repo package_name

  if [[ "$pkg" == */* ]]; then
    package_repo="${pkg%%/*}"
    package_name="${pkg##*/}"
  else
    package_repo=""
    package_name="$pkg"
  fi

  for i in "${!REPO_URLS[@]}"; do
    local repo_name="${REPO_NAMES[$i]}"
    [[ -n "$package_repo" && "$repo_name" != "$package_repo" ]] && continue

    local pkg_dir="$PPM_DATA_HOME/$repo_name/packages/$package_name"
    if [[ -d "$pkg_dir" ]]; then
      FOUND_REPO_NAME="$repo_name"
      echo "$pkg_dir"
      return 0
    fi
  done

  return 1
}
```

#### `resolve_deps()`

Recursive resolution with cycle detection:

```bash
# Resolve full dependency tree for a list of packages
# Populates RESOLVED_PACKAGES (associative array: key=repo/name, value=pkg_dir)
# and RESOLVE_ORDER (indexed array preserving discovery order)
# Usage: resolve_deps pkg1 [pkg2 ...]
declare -A RESOLVED_PACKAGES
declare -a RESOLVE_ORDER
declare -A _RESOLVING  # cycle detection: packages currently being resolved

resolve_deps() {
  for pkg in "$@"; do
    _resolve_one "$pkg"
  done
}

_resolve_one() {
  local pkg="$1"
  local pkg_dir repo_name qualified_name

  pkg_dir=$(find_package_dir "$pkg") || {
    echo "Error: Package '$pkg' not found" >&2
    exit 1
  }
  qualified_name="${FOUND_REPO_NAME}/${pkg##*/}"

  # Already resolved — skip
  [[ -n "${RESOLVED_PACKAGES[$qualified_name]+x}" ]] && return 0

  # Cycle detection
  if [[ -n "${_RESOLVING[$qualified_name]+x}" ]]; then
    echo "Error: Circular dependency detected: $qualified_name" >&2
    exit 1
  fi
  _RESOLVING["$qualified_name"]=1

  # Resolve dependencies first (depth-first)
  local deps
  deps=$(resolve_package_deps "$pkg_dir")
  if [[ -n "$deps" ]]; then
    for dep in $deps; do
      _resolve_one "$dep"
    done
  fi

  # Mark as resolved
  unset '_RESOLVING[$qualified_name]'
  RESOLVED_PACKAGES["$qualified_name"]="$pkg_dir"
  RESOLVE_ORDER+=("$qualified_name")

  debug "Resolved: $qualified_name -> $pkg_dir"
}
```

Key behaviors:
- **Deduplication**: `RESOLVED_PACKAGES` is an associative array — each package appears once.
- **Cycle detection**: `_RESOLVING` tracks the current resolution stack. If we encounter a package already being resolved, it's a cycle.
- **Depth-first**: dependencies are resolved before the package itself, naturally producing a bottom-up order.
- **Repo precedence**: `find_package_dir` searches repos in sources.list order, so the first match wins (same as current behavior).

### 2. Add a `ppm deps` command for testing/debugging

Temporary or permanent command that shows the resolved dependency tree without installing:

```bash
deps() {
  if [[ $# -eq 0 ]]; then
    echo "Usage: ppm deps <package> [package...]"
    exit 1
  fi

  collect_repos

  declare -A RESOLVED_PACKAGES
  declare -a RESOLVE_ORDER
  declare -A _RESOLVING

  resolve_deps "$@"

  echo "Install order (${#RESOLVE_ORDER[@]} packages):"
  for pkg in "${RESOLVE_ORDER[@]}"; do
    echo "  $pkg"
  done
}
```

Add `deps` to the command list and completions.

### 3. Test with real package trees

Expected resolution for `ppm deps rails`:
```
pde-ppm/mise
pde-ppm/ruby
pde-ppm/rails
```

Expected resolution for `ppm deps rws`:
```
pde-ppm/mise
pde-ppm/ruby
rjayroach-ppm/chorus  (or pde-ppm/chorus depending on source order)
... gems, network, podman, tailscale and their transitive deps
rjayroach-ppm/rws
```

Expected resolution for `ppm deps claude ruby` (shared dep):
```
pde-ppm/mise        ← appears once despite both needing it
pde-ppm/claude
pde-ppm/ruby
```

## Test Spec

- `ppm deps rails` → shows mise, ruby, rails in order
- `ppm deps claude ruby` → mise appears once, before both claude and ruby
- `ppm deps nonexistent` → "Error: Package 'nonexistent' not found"
- Create a temp circular dep (A depends B, B depends A) → "Error: Circular dependency detected"
- `ppm deps pde-ppm/git` → resolves from the specific repo

## Verification

- [ ] `lib/graph.sh` exists with `find_package_dir`, `resolve_deps`, `_resolve_one`
- [ ] `ppm deps rails` produces correct ordered, deduplicated output
- [ ] Shared dependencies appear exactly once
- [ ] Circular dependency detection works
- [ ] Missing package detection works with clear error message
- [ ] `--debug` shows resolution steps
