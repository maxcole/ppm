---
status: complete
started_at: "2026-03-20T22:57:53+08:00"
completed_at: "2026-03-20T23:02:12+08:00"
deviations: "Used existing declare-f dispatch pattern with backend_command fallback instead of case statement. cmd_down uses while loop instead of C-style for loop (bash 3.2 compat). Added _parse_service_arg helper and _resolve_lifecycle_network helper for cleaner network/service disambiguation."
summary: Added service lifecycle commands (up, down, restart, logs, status) with dependency-aware ordering, auto-install, and network disambiguation
---

# Execution Log

## What Was Done

- Added `backend_command()` dispatch to `lib/services/service.sh` — handles up, down, restart, logs, status
- Updated main ppm script dispatch to fall through to `backend_command()` for unknown commands
- Implemented `cmd_up` — dependency-aware startup via resolve_deps, auto-installs missing services
- Implemented `cmd_down` — reverse dependency order shutdown
- Implemented `cmd_restart` — down + up
- Implemented `cmd_logs` — compose logs with network disambiguation
- Implemented `cmd_status` — shows all services grouped by network, or specific service status
- Added `_find_installed_network()` — finds which network a service is installed on, errors on ambiguity
- Added `_parse_service_arg()` — parses `network/service` syntax for explicit network specification
- Added `_resolve_lifecycle_network()` — resolves network from explicit arg, dep tree, or installed dirs
- Registered `--up` flag in `parse_backend_flag()` via `PSM_START_AFTER_INSTALL`
- Added `--up` support in `install()` — calls `cmd_up` for each expanded package after install completes
- Updated `list_commands()` to show lifecycle commands when backend_command is available

## Test Results

- `psm up hello` → pulls image, starts container ✓
- `psm status` → shows services grouped by network with status ✓
- `psm logs psm/hello` → shows container output ✓
- `psm down hello` → stops container ✓
- `psm restart hello` → cycles service ✓
- `psm up mystack` → starts hello (dep) first, then mystack, both on mystack network ✓
- `psm down mystack` → stops mystack first, then hello (reverse order) ✓
- `psm up hello` (not installed) → auto-installs then starts ✓
- `psm install --up hello` → installs and starts ✓
- `psm logs hello` (on multiple networks) → "exists on multiple networks" with disambiguation help ✓
- `psm logs psm/hello` → works with explicit network ✓
- `ppm up test` → "Error: Unknown command 'up'" ✓
- Help text includes lifecycle commands for psm, not for ppm ✓
- `ppm install -s zsh` → still works ✓

## Notes

The hello-world container exits immediately after printing, so `psm status` shows "stopped" — this is correct behavior for that image. A long-running service like postgres would show "running".

`profile_install` skips if `data/` dir exists (idempotency check). After `psm remove`, data is preserved but registry/config are removed. A subsequent install needs the data dir fully removed to trigger a fresh install. This is by design — data preservation is a safety feature.

## Context Updates

- Service lifecycle commands available: `psm up`, `psm down`, `psm restart`, `psm logs`, `psm status`.
- `psm up` resolves dependencies and starts in topological order. Auto-installs missing services.
- `psm down` stops in reverse dependency order.
- `psm status` (no args) shows all services grouped by network. `psm status <service>` shows specific service.
- `network/service` syntax disambiguates when a service is on multiple networks (e.g., `psm logs psm/hello`).
- `psm install --up <service>` installs and starts in one command.
- Backend command dispatch uses `backend_command()` hook — main script falls through to it for unknown commands.
- `list_commands()` conditionally shows lifecycle commands when backend is loaded.
