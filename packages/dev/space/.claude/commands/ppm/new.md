---
description: Create a new PPM package with scaffolding
---

# PPM Package Creation

You are creating a new PPM package. First, read the PPM specification:

```
cat ~/.claude/docs/ppm.md
```

## Package Details

Create a package named: $ARGUMENTS

## Process

1. **Research Phase** (if the package installs software):
   - Search for official installation instructions for the software
   - Identify the latest stable version
   - Note any platform-specific differences (linux vs macos)
   - Identify dependencies

2. **Design Phase**:
   - Decide what config files belong in `home/`
   - Identify if there are dependencies on other packages
   - Determine if mise can manage the tool version
   - Consider if shell integration is needed (`.config/zsh/<name>.zsh`)

3. **Scaffold the Package**:
   ```bash
   mkdir -p packages/<name>/home/.config/<name>
   ```

4. **Create install.sh** with appropriate lifecycle hooks:
   - Use `dependencies()` for other ppm packages
   - Use `install_dep` for system packages (apt/brew)
   - Prefer mise for version-managed tools (node, ruby, python, etc.)
   - Use `post_install()` for setup that runs after stow

5. **Create Configuration Files**:
   - Add sensible defaults in `home/.config/<name>/`
   - Add shell aliases/functions in `home/.config/zsh/<name>.zsh` if needed
   - Add mise config in `home/.config/mise/conf.d/<name>.toml` if using mise

6. **Test the Package**:
   ```bash
   ppm install <name>
   # Verify symlinks created
   ls -la ~/.config/<name>
   # Verify software works
   <name> --version
   ```

7. **Document** any manual setup steps in a comment at the top of install.sh

## Output

Present the complete package structure and all file contents for review before creating.
