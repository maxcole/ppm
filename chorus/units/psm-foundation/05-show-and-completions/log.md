---
status: complete
started_at: "2026-03-21T06:31:31+08:00"
completed_at: "2026-03-21T06:34:40+08:00"
deviations: null
summary: Added backend_show() for service-specific show output and backend_completion() for PSM zsh completions
---

# Execution Log

## What Was Done

- Added `backend_show()` to `lib/services/service.sh` — displays service metadata from `psm.yml` (description, ports), network assignment, PCM credential presence, resolved dependency tree, and installed instance status with running/stopped detection
- Added `backend_completion()` to `lib/services/service.sh` — generates zsh completion for all PSM commands (install, remove, up, down, restart, logs, status, etc.) with service name completion from repos and installed instances
- Modified `ppm` main script `show()` to call `backend_show()` after generic display when available
- Modified `ppm` main script `completion()` to delegate to `backend_completion()` when available
- Updated `packages/psm/home/.config/zsh/psm/psm.zsh` to load PSM completions via `eval "$(ppm completion zsh)"`
- PPM package backend is completely unaffected — `ppm show` and `ppm completion zsh` still work for packages

## Test Results

- `bash -n` syntax check passes for all modified files
- `ppm list` works correctly
- `ppm show psm` works correctly (package backend)
- `ppm completion zsh` outputs valid ppm completions (no backend loaded)
- PSM completion (`ppm completion zsh` with service env vars) outputs valid `#compdef psm` zsh completion
- Runtime `psm show postgres` requires psm sources/data to be set up (not available on this machine)

## Notes

The completion function lists service names without repo prefix (just `postgres` not `psm-ppm/postgres`) for ease of use, plus `network/service` format for installed instances to enable disambiguation.

## Context Updates

- `backend_show()` in `lib/services/service.sh` provides enhanced show output for services: metadata from `psm.yml`, network info, credential detection, resolved dep tree, and instance status.
- `backend_completion()` in `lib/services/service.sh` generates zsh completions for all PSM commands and service names.
- The main `ppm` script dispatches to `backend_show()` and `backend_completion()` when the service backend is loaded.
- `packages/psm/home/.config/zsh/psm/psm.zsh` now loads PSM completions on shell init.
