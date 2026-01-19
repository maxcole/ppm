# PPM Development Space

This is a workspace for developing and maintaining PPM (Personal Package Manager) and its ecosystem of package repositories.

## Directory Structure

```
~/spaces/ppm/
├── CLAUDE.md           # This file (symlinked from dev package)
├── .claude/            # Claude configuration (symlinked from dev package)
├── .obsidian/          # Obsidian vault settings for this space
├── repos/              # → ~/.local/share/ppm (all PPM repositories)
│   ├── ppm/            # Main PPM tool and core packages
│   ├── pde-ppm/        # Personal Development Environment packages
│   ├── pdt-ppm/        # Personal Dev Tools packages
│   ├── lgat-ppm/       # LGAT packages
│   ├── pcs-ppm/        # PCS packages
│   ├── rjayroach-ppm/  # rjayroach packages
│   ├── roteoh-ppm/     # roteoh packages
│   └── rws-ppm/        # RWS packages
└── bases/              # Knowledge bases (documentation separate from code)
    ├── pde/            # → iCloud Obsidian vault for PDE docs
    └── pdt/            # → iCloud Obsidian vault for PDT docs
```

## Knowledge Bases (bases/)

The `bases/` directory contains symlinks to Obsidian vaults that hold documentation and project management content separate from the code repositories. This separation allows:

- Documentation to be edited and synced via Obsidian across devices
- Agile boards and project tracking alongside technical docs
- Rich markdown editing with Obsidian plugins
- Clear boundary between code (repos/) and documentation (bases/)

### Base Structure

Each knowledge base typically contains:
- `product/` - Product documentation, specs, and design docs
- `inbox/` - Incoming notes and items to be triaged
- `references/` - Reference materials and external documentation
- `_docs/` - Generated or structured documentation

## Working with Repositories

Each repository in `repos/` is a PPM package repository containing:
- `packages/` - Directory of installable packages
- `README.md` - Repository description

The main `ppm` repository additionally contains:
- `ppm` - The main executable script
- `ppm.conf` - Default configuration
- `sources.list` - Default repository sources
- `CLAUDE.md` - Detailed PPM documentation (see below)

## PPM Documentation

For detailed information about PPM commands, package structure, and lifecycle hooks, see:
- `repos/ppm/CLAUDE.md` - Complete PPM reference

## Workflow

1. **Code changes**: Work in `repos/<repo-name>/packages/<package>/`
2. **Documentation**: Edit in `bases/<base-name>/` via Obsidian or directly
3. **Testing**: Use `ppm install` and `ppm remove` to test packages
4. **Cross-reference**: Link documentation in bases to code in repos
