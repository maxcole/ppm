---
objective: You can build on it — ppm is a configurable engine that supports multiple asset backends
status: complete
---

Platform tier for PPM engine extraction. Refactors the ppm script and libraries to be domain-agnostic, driven by environment variables rather than hardcoded package/stow assumptions. After this tier, ppm can manage packages (stow-based dotfiles) or services (compose-based containers) depending on how it is invoked.

This tier does NOT implement the service backend or PSM functionality. It only makes ppm's internals configurable so that a service backend CAN be added (tier: psm-foundation).

See `docs/adr/001-ppm-as-configurable-engine.md` for the full architectural decision record.

## Completion Criteria

- ppm script accepts `PPM_CONFIG_HOME`, `PPM_DATA_HOME`, `PPM_ASSET_DIR`, `PPM_ASSET_HOOK`, `PPM_ASSET_LABEL` from environment with backward-compatible defaults
- `lib/repo.sh` scans `$PPM_ASSET_DIR` (not hardcoded `packages`) in repos
- `installer()` and `remover()` are extracted from the main script into `lib/installer.sh`
- Stow-specific logic is extracted into `lib/packages/stow.sh` and defines `profile_install()` and `profile_remove()`
- `installer()` calls `profile_install()` instead of inline stow logic
- Backend-specific libraries are sourced from `lib/$PPM_ASSET_DIR/` when that directory exists
- The `ppm` zsh function in `packages/ppm/home/.config/zsh/ppm.zsh` is updated (no behavior change needed — defaults are correct)
- A `psm` package is created in `packages/psm/` that stows a `psm.zsh` shell function
- All existing ppm commands work identically — `ppm list`, `ppm install`, `ppm remove`, `ppm show`, `ppm deps`, `ppm update`, `ppm src`
- All existing packages install correctly with no changes to package repos
