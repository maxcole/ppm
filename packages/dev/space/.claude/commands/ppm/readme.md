---
description: Generate a README.md for a PPM package (for GitHub/developer audience)
---

# PPM Package README Generator

Generate a README.md for a package that helps developers understand what it does and how to use it.

## Package

$ARGUMENTS

## Process

1. **Inspect the package**:
   ```bash
   # Read install.sh to understand what it does
   cat packages/$ARGUMENTS/install.sh 2>/dev/null
   
   # See what config files are included
   find packages/$ARGUMENTS/home -type f 2>/dev/null
   ```

2. **Generate README.md** with these sections:

### README Structure

```markdown
# <Package Name>

One-line description of what this package provides.

## What's Included

- List of key config files or tools installed
- Notable features or customizations

## Dependencies

List any PPM package dependencies (from `dependencies()` function).

## Installation

```bash
ppm install <package-name>
```

## Configuration

Describe any post-install configuration needed:
- Environment variables to set
- Manual steps required
- Files the user might want to customize

## Files

| Path | Description |
|------|-------------|
| `~/.config/<app>/...` | Brief description |
| `~/.local/bin/...` | Brief description |

## Usage

Show common usage examples if applicable (commands, aliases, etc.)

## Customization

Point out which files users might want to modify for their own preferences.
```

3. **Write the README**:
   ```bash
   # Write to package directory
   cat > packages/$ARGUMENTS/README.md << 'EOF'
   <generated content>
   EOF
   ```

## Guidelines

- Be concise - developers skim READMEs
- Focus on "what" and "how", not implementation details
- Include practical examples over exhaustive documentation
- Mention any gotchas or prerequisites
- Link to upstream documentation for the underlying tool if relevant
