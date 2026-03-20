---
objective: It works — ppm script is modular, metadata exists, dependencies resolved from YAML
status: complete
---

Foundation tier for package metadata and ppm script modernization.

Restructures the monolithic ppm script into libraries, introduces `package.yml` metadata files across all package repos, migrates dependency declarations from bash functions to YAML, adds sources.list aliasing, auto-update timer, debug logging, user message aggregation, and installed-package tracking.

## Completion Criteria

- ppm script is split into entrypoint + `lib/*.sh` with clean separation of concerns
- All space-related dead code removed from ppm
- `sources.list` supports two-column format (URL + alias) and existing single-column still works
- `ppm update` runs on a configurable timer like brew
- `--debug` flag enables verbose logging; `user_message` aggregates package messages for end-of-run display
- Every package across pde-ppm, pdt-ppm, rjayroach-ppm has a `package.yml` with version and author
- `dependencies()` functions migrated from `install.sh` to `depends` in `package.yml`
- `installer()` reads deps from `package.yml` via yq, falls back to `install.sh`
- `$PPM_DATA_HOME/.installed.yml` tracks installed packages and versions
- `ppm list --installed` works
