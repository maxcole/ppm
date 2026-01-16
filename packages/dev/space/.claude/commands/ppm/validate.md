---
description: Validate a PPM package against conventions and best practices
---

# PPM Package Validation

Validate the specified package against PPM conventions.

```
cat ~/.claude/docs/ppm.md
```

## Package to Validate

$ARGUMENTS

## Validation Checks

Run through these checks and report findings:

### 1. Structure Validation
- [ ] Package directory exists at `packages/<n>/`
- [ ] If `home/` exists, it mirrors `$HOME` structure correctly
- [ ] No files at package root that should be in `home/` (e.g., stray config files)

### 2. install.sh Validation (if present)
```bash
# Check syntax
bash -n packages/<n>/install.sh
```

- [ ] Valid bash syntax
- [ ] Functions use correct names (`dependencies`, `pre_install`, `install_linux`, `install_macos`, `post_install`, etc.)
- [ ] `dependencies()` returns space-separated package names (not commands)
- [ ] `install_dep` used for system packages, not `apt install` or `brew install` directly
- [ ] Uses `$(os)` and `$(arch)` helpers where appropriate
- [ ] Uses XDG variables (`$XDG_CONFIG_HOME`, etc.) not hardcoded paths
- [ ] Commands check if already installed before reinstalling (idempotent)

### 3. Symlink Target Validation
- [ ] Files in `home/` won't conflict with other packages
- [ ] Config directories use appropriate nesting (`.config/<app>/` not `.config-<app>/`)
- [ ] Executable scripts in `home/.local/bin/` are actually executable

### 4. Dependency Validation
```bash
# Check if declared dependencies exist
source packages/<n>/install.sh 2>/dev/null
deps=$(dependencies 2>/dev/null || echo "")
for dep in $deps; do
  ppm list | grep -q "$dep" || echo "Missing dependency: $dep"
done
```

### 5. Best Practices
- [ ] Has meaningful comments in install.sh
- [ ] Doesn't pollute `$HOME` root (uses `.config/`, `.local/`, etc.)
- [ ] Sensitive defaults are in `.env.example`, not hardcoded
- [ ] Version-managed tools use mise, not direct installation
- [ ] Shell integration via `.config/zsh/<n>.zsh`, not `.zshrc` modifications

## Output

Provide a validation report with:
1. ✅ Passed checks
2. ⚠️ Warnings (recommendations)
3. ❌ Errors (must fix)
4. Suggested improvements
