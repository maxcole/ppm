---
status: complete
started_at: "2026-03-16T08:28:57+08:00"
completed_at: "2026-03-16T08:30:54+08:00"
deviations: "Plan specified associative arrays (declare -A) which require bash 4+. Reimplemented using newline-separated strings and grep for bash 3.2 compatibility. find_package_dir outputs repo_name<TAB>pkg_dir instead of using a side-effect variable (subshell issue)."
summary: Created lib/graph.sh with dependency resolution, deduplication, and cycle detection; added ppm deps command
---

# Execution Log

## What Was Done

- Created `lib/graph.sh` with bash 3.2-compatible implementation:
  - `find_package_dir()` — locates package dir by searching repos in source order, outputs `repo_name<TAB>pkg_dir`
  - `resolve_deps()` — entry point, resets state and resolves each requested package
  - `_resolve_one()` — recursive depth-first resolution with dedup and cycle detection
- Uses newline-separated strings (`_RESOLVED`, `_RESOLVING`) with `grep -qxF` instead of associative arrays
- Populates parallel arrays `RESOLVE_ORDER` (qualified names) and `RESOLVE_DIRS` (paths)
- Added `ppm deps` command for debugging/inspecting dependency trees
- Added `deps` to command list

## Test Results

- `ppm deps rails` → zsh, mise, ruby, rails in correct order ✓
- `ppm deps pde-ppm/claude ruby` → mise appears once (deduplication) ✓
- `ppm deps nonexistent` → "Error: Package 'nonexistent' not found" ✓
- Circular dependency → "Error: Circular dependency detected: cycle-test/alpha" ✓
- `ppm deps pde-ppm/git` → resolves from specific repo ✓
- `ppm deps --debug rails` → shows resolution steps ✓

## Context Updates

- `lib/graph.sh` provides dependency graph resolution with deduplication and cycle detection.
- `find_package_dir()` searches repos in sources.list order (first match wins), outputs `repo_name<TAB>pkg_dir`.
- `resolve_deps()` populates `RESOLVE_ORDER` (qualified names like `pde-ppm/ruby`) and `RESOLVE_DIRS` (parallel array of paths) in topological install order (deps first).
- `ppm deps <package> [package...]` command shows resolved install order without installing.
- Implementation is bash 3.2-compatible (no associative arrays).
