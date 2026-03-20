---
status: complete
started_at: "2026-03-20T21:48:31+08:00"
completed_at: "2026-03-20T21:57:12+08:00"
deviations: "Plan used associative arrays (declare -A RESOLVED_PACKAGES) but bash 3.2 compat required parallel indexed arrays. Used existing RESOLVE_DIRS from graph.sh instead. Skip-deps path uses find_package_dir() with tab-separated output parsing instead of the plan's FOUND_REPO_NAME variable which doesn't exist."
summary: Rewrote install() to use dependency graph, extracted install_single_package(), removed old installer()
---

# Execution Log

## What Was Done

- Rewrote `install()` to call `resolve_deps()` for full dependency graph resolution before installing anything
- Added skip-deps (`-s`) path that uses `find_package_dir()` to resolve only requested packages without transitive deps
- Prints install plan summary ("Installing N package(s):") before starting
- Iterates `RESOLVE_ORDER`/`RESOLVE_DIRS` in topological order, calling `install_single_package()` for each
- Extracted `install_single_package()` from the old `installer()` inner loop — handles stow-only packages, pre_install/post_install hooks, OS-specific install, stowed file tracking, and stale file cleanup
- Removed old `installer()` function and all `"$0" "installer"` recursive subprocess calls
- Preserved all existing behavior: `ignore_args` scoping, `PPM_CURRENT_PACKAGE` setting, `meta_cleanup_stale`, `meta_mark_installed` with stowed files

## Test Results

- `ppm install rails` → zsh, mise, ruby, rails in correct order; each exactly once ✓
- `ppm deps claude ruby` → mise appears once (dedup) ✓
- `ppm install -s rails` → installs only rails, skips deps ✓
- `ppm install -f -s rails` → force mode works ✓
- `ppm install -r -s rails` → reinstall (remove + install) works ✓
- `ppm install -c rails` → config-only (no hooks executed) works ✓
- `ppm remove rails` → remover unchanged, works ✓
- `ppm list --installed` → shows tracked packages ✓
- `--debug` shows resolution and install sequence ✓

## Notes

The plan's code snippets assumed bash 4+ associative arrays (`declare -A RESOLVED_PACKAGES`), but plan 01 already solved this by using parallel indexed arrays (`RESOLVE_ORDER` + `RESOLVE_DIRS`). The implementation uses those directly.

The `config_flag` variable is accessed in `install_single_package()` subshells via the caller's scope (not passed as an argument). This works because subshells inherit the parent's variables, and `config_flag` is set in `main()` before `install()` is called.

## Context Updates

- `install()` now resolves the full dependency graph via `resolve_deps()` before installing anything — no more recursive subprocess calls.
- `install_single_package()` is the per-package install function, handling stow, hooks, OS-specific install, and tracking.
- The old `installer()` function and `"$0" "installer"` recursive pattern are removed.
- Install flow: expand packages → resolve graph → print plan → iterate in topo order → flush messages.
- `RESOLVE_ORDER` and `RESOLVE_DIRS` (from `lib/graph.sh`) drive the install loop.
