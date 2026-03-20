---
status: complete
started_at: "2026-03-20T22:46:32+08:00"
completed_at: "2026-03-20T22:52:48+08:00"
deviations: "Dropped -s alias for --skip-validation to avoid conflict with ppm's -s (skip_deps). Network context propagation moved from install_single_package() to install() — scans EXPANDED_PACKAGES before the install loop so deps inherit the network from the top-level requested package."
summary: Created service backend libraries (scope, network, compose, service) with profile_install/profile_remove, backend flag parsing, and network isolation
---

# Execution Log

## What Was Done

- Created `lib/services/scope.sh` with scope resolution (user/system), `parse_backend_flag()` for `--user`/`--system`/`--skip-validation` flags, auto-resolves on source
- Created `lib/services/network.sh` with Podman network creation (`_ensure_network`), network key reading from package.yml (`_service_network`), and context-aware resolution (`_resolve_network`)
- Created `lib/services/compose.sh` with podman requirement checking, env file builder (PSM vars + .env.example + user overrides), compose file discovery, and compose runner with varlock integration path
- Created `lib/services/service.sh` with `profile_install()` (creates instance dirs, links registry) and `profile_remove()` (stops containers, removes instance, preserves data)
- Updated main ppm script's flag parser to call `parse_backend_flag()` for unrecognized `--*` flags
- Added `_resolve_scope` re-call after flag parsing so `--user`/`--system` takes effect
- Added network context propagation in `install()` — scans requested packages for `network:` key in package.yml, sets `_PSM_INSTALL_NETWORK` so all deps install under the same network

## Test Results

- `psm list` → shows `test-psm/hello`, `test-psm/mystack` ✓
- `psm install hello` → creates `services/psm/hello/{config,data,registry}` ✓
- Registry symlink → points to source repo service definition ✓
- `psm install mystack` (network: mystack, depends: hello) → both services under `services/mystack/` ✓
- Podman network `mystack` created automatically ✓
- `psm list --installed` → shows both services with versions ✓
- `psm show hello` → metadata and install status ✓
- `psm remove hello` → removes instance, preserves data ✓
- `psm list --user` → flag parsed correctly ✓
- `ppm list` → unaffected ✓
- `ppm install zsh` → unaffected ✓

## Notes

The `--user`/`--system` flags must come after the command (e.g., `psm list --user`), not before, because the main script extracts `$1` as the command before flag parsing.

Local path repos in `sources.list` require manual symlinking into `$PPM_DATA_HOME/<alias>` since `update()` only handles git URLs. This is by design — local paths are for development/testing.

## Context Updates

- `lib/services/` contains the service backend: `scope.sh`, `network.sh`, `compose.sh`, `service.sh`.
- Service `profile_install()` creates `$PSM_SERVICES_HOME/<network>/<service>/{config,data,registry}` where registry is a symlink to the source repo definition.
- Service `profile_remove()` stops containers and removes instance but preserves `data/` directory.
- Network isolation: services with `network: <name>` in `package.yml` scope all their dependencies under that network directory. Network context propagated via `_PSM_INSTALL_NETWORK` variable.
- Backend-specific flags are parsed via `parse_backend_flag()` hook called from the main script's flag loop. Services add `--user`, `--system`, `--skip-validation`.
- `_resolve_scope()` runs on source and again after flag parsing, setting `PSM_HOME` and `PSM_SERVICES_HOME`.
- `_compose_run()` handles env injection (PSM vars + .env.example + user overrides) and optional varlock validation.
- `_require_podman()` checks for `podman` and `podman-compose` before any service operations.
