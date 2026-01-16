---
description: Show structure and contents of an existing PPM package
---

# PPM Package Inspection

Inspect an existing package to understand its structure.

## Package to Inspect

$ARGUMENTS

## Actions

1. **Show package tree**:
   ```bash
   find packages/$ARGUMENTS -type f | head -50
   ```

2. **Display install.sh** (if exists):
   ```bash
   cat packages/$ARGUMENTS/install.sh 2>/dev/null || echo "No install.sh"
   ```

3. **List home/ contents** (symlink targets):
   ```bash
   find packages/$ARGUMENTS/home -type f 2>/dev/null | sed 's|packages/[^/]*/home/||'
   ```

4. **Show key config files**:
   - Shell integration: `cat packages/$ARGUMENTS/home/.config/zsh/*.zsh 2>/dev/null`
   - Mise config: `cat packages/$ARGUMENTS/home/.config/mise/conf.d/*.toml 2>/dev/null`

5. **Check if installed**:
   ```bash
   # Look for symlinks pointing to this package
   find ~ -maxdepth 4 -type l -ls 2>/dev/null | grep "ppm.*packages/$ARGUMENTS" | head -10
   ```

## Output

Provide a summary of:
- What the package installs
- Its dependencies
- What symlinks it creates
- How it integrates with shell/tools
- Any notable implementation patterns
