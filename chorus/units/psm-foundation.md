---
objective: It works — psm can install, start, stop, and manage containerized services using the ppm engine
status: in_progress
---

PSM foundation tier. Implements the service backend for the ppm engine, enabling management of containerized services via Podman and compose files. PSM reuses ppm's repo management, dependency resolution, source precedence, and install tracking, adding service-specific behavior: compose lifecycle, scope resolution, network management, env var injection, and varlock/PCM integration.

Depends on: platform tier (ppm engine extraction) being complete.

See `docs/adr/001-ppm-as-configurable-engine.md` for the full architectural decision record.

## Completion Criteria

- Service backend libraries exist in `lib/services/` defining `profile_install()` and `profile_remove()`
- `psm install <service>` resolves dependencies, creates instance directories (config/, data/), links registry definitions
- `psm up <service>` starts services in dependency order via podman-compose
- `psm down <service>` stops services in reverse dependency order
- `psm logs <service>` and `psm status [<service>]` work
- `psm restart <service>` works (down + up)
- Services join a shared Podman network (`psm` by default)
- Network isolation via `network` key in `package.yml` — meta-services can declare isolated networks
- `--user`/`--system` scope flags work, with system scope targeting `/opt/psm/`
- Varlock integration: when varlock is present, compose runs through `varlock run --`
- Env vars injected into compose: `PSM_DATA`, `PSM_CONFIG`, `PSM_CACHE`, `PSM_SERVICE`, `PSM_NETWORK`, `PSM_TYPE`
- `psm install <service> --up` installs and starts
- `psm up <service>` auto-installs if not installed
- `psm list` shows available services from source repos
- `psm list --installed` shows installed services with running status
- `psm show <service>` shows metadata, deps, resolved tree, and running status
- A starter `psm-ppm` service repo exists with at least postgres as a working service
- `psm` zsh completions work for commands and service names
