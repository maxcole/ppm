---
description: Patterns and workflows for creating and maintaining PPM packages
globs:
  - "**/packages/*/install.sh"
  - "**/packages/*/home/**"
  - "**/packages/*/space/**"
alwaysApply: false
---

# PPM Package Authoring

## When to Use This Skill

Activate when:
- Creating a new ppm package
- Modifying an existing package's install.sh or structure
- Adding integrations (shell, mise, claude, chorus, tmuxinator)
- Troubleshooting package installation issues
- Converting manual setup steps into a package

**Prerequisite**: Read `~/.claude/skills/ppm/SKILL.md` first for core concepts.

## Package Creation Workflow

### 1. Research Phase (for software packages)
- Find official installation instructions
- Identify latest stable version
- Note platform differences (linux vs macos)
- Check if mise can manage versions
- Identify system dependencies (apt/brew packages)

### 2. Design Decisions

**Q: Does this need install.sh?**
- No: Pure dotfiles/config only → just use `home/`
- Yes: Needs dependencies, downloads, or post-setup

**Q: Should mise manage this tool?**
- Yes if: node, ruby, python, rust, go, or any mise-supported tool
- Pattern: `dependencies()` returns the runtime, `post_install()` runs mise/gem/npm

**Q: Does it need shell integration?**
- Yes if: aliases, functions, PATH modifications, completions
- Location: `home/.config/zsh/<n>.zsh`

### 3. Scaffold

```bash
# Minimal (config only)
mkdir -p packages/<n>/home/.config/<n>

# With shell integration
mkdir -p packages/<n>/home/.config/{<n>,zsh}

# With mise tool
mkdir -p packages/<n>/home/.config/{<n>,mise/conf.d}

# Full structure
mkdir -p packages/<n>/{home/.config/<n>,space}
touch packages/<n>/install.sh
```

### 4. Test Cycle
```bash
ppm install <n>           # Test install
ppm remove <n>            # Test clean removal  
ppm install -f <n>        # Test force reinstall
ppm install -c <n>        # Test config-only mode
```

## Common Patterns

### Pattern: Dotfiles Only (no install.sh)
```
packages/git/
└── home/.config/git/
    ├── config
    └── ignore
```

### Pattern: Shell Integration
```bash
# packages/foo/home/.config/zsh/foo.zsh
export FOO_HOME="$XDG_DATA_HOME/foo"
alias foo='foo --config $XDG_CONFIG_HOME/foo/config'

# Lazy-load completions (performance)
foo() {
  unfunction foo
  eval "$(foo --completions zsh)"
  foo "$@"
}
```

### Pattern: Mise-Managed Tool
```bash
# packages/node/install.sh
post_install() {
  source <(mise activate zsh)
  mise install node
}
```
```toml
# packages/node/home/.config/mise/conf.d/node.toml
[tools]
node = "22"
```

### Pattern: Gem/NPM Tool
```bash
# packages/tmuxinator/install.sh
dependencies() {
  echo "ruby"  # Ensure ruby package installed first
}

post_install() {
  source <(mise activate zsh)
  gem install tmuxinator
}
```

### Pattern: Binary Download
```bash
# packages/tool/install.sh
install_linux() {
  command -v tool &> /dev/null && return
  
  local arch="amd64"
  [[ "$(arch)" == "arm64" ]] && arch="arm64"
  
  curl -fsSL -o "$BIN_DIR/tool" \
    "https://example.com/releases/tool-linux-${arch}"
  chmod +x "$BIN_DIR/tool"
}

install_macos() {
  install_dep tool  # Prefer brew when available
}
```

### Pattern: AppImage (Linux)
```bash
install_linux() {
  curl -fsSL -o "$BIN_DIR/app" \
    "https://example.com/app.AppImage"
  chmod +x "$BIN_DIR/app"
}
```

### Pattern: Meta-Package (install all in repo)
```bash
# packages/all/install.sh
dependencies() {
  ppm list $(repo_name) | cut -d'/' -f2 | grep -v '^all$'
}

repo_name() {
  basename "$(dirname "$(dirname "$(dirname "${BASH_SOURCE[0]}")")")"
}
```

### Pattern: Project Workspace
```bash
# packages/myproject/install.sh
space_path() {
  echo "$HOME/spaces/myproject"
}

space_install() {
  # Runs from within space_path
  git clone https://github.com/org/repo repos/main
  cp space.yml.example space.yml
}
```
```
packages/myproject/
├── install.sh
├── home/.config/tmuxinator/myproject.yml
└── space/
    ├── CLAUDE.md
    └── space.yml.example
```

### Pattern: Claude Code Integration
```
packages/dev/home/.claude/
├── commands/namespace/
│   ├── action1.md
│   └── action2.md
├── docs/
│   └── reference.md
└── skills/namespace/
    └── SKILL.md
```

### Pattern: Chorus Integration
```yaml
# packages/foo/home/.config/chorus/hubs.d/foo.yml
foo:
  root: ~/spaces/foo

# packages/foo/home/.config/chorus/repos.d/foo.yml  
foo:
  - name: main
    url: git@github.com:org/foo.git
```

### Pattern: Tmuxinator Session
```yaml
# packages/foo/home/.config/tmuxinator/foo.yml
name: foo
root: ~/spaces/foo
windows:
  - editor:
      panes:
        - nvim
  - shell:
```

## Cross-Platform Considerations

### Prefer mise over manual installs
```bash
# Good: mise handles platform differences
post_install() {
  source <(mise activate zsh)
  mise install rust
}

# Avoid: manual platform branching for mise-supported tools
install_linux() { ... }
install_macos() { ... }
```

### Use install_dep for system packages
```bash
# Good: install_dep handles apt vs brew
install_linux() {
  install_dep build-essential libssl-dev
}
install_macos() {
  install_dep openssl
}
```

### Check before installing
```bash
install_linux() {
  command -v tool &> /dev/null && return  # Skip if exists
  # ... install
}
```

## Troubleshooting

### Stow conflicts
```bash
# See what's conflicting
stow -n -v -d packages/<n> -t $HOME home

# Force overwrite (removes existing files)
ppm install -f <n>
```

### Debug install.sh
```bash
# Run with debug output
bash -x packages/<n>/install.sh
```

### Check symlink targets
```bash
ls -la ~/.config/<n>/
# Should show: -> /path/to/ppm/<repo>/packages/<n>/home/.config/<n>/file
```

### Package not found
```bash
ppm list           # See all available
ppm list <filter>  # Filter by name
ppm update         # Refresh repos
```

## Checklist Before Committing

- [ ] `ppm install <n>` works cleanly
- [ ] `ppm remove <n>` removes all symlinks
- [ ] `ppm install -f <n>` works (force reinstall)
- [ ] `ppm install -c <n>` works (config-only, if applicable)
- [ ] Tested on target platform(s)
- [ ] No hardcoded paths (use XDG variables)
- [ ] Dependencies declared in `dependencies()`
- [ ] README.md documents usage (run `/ppm readme <n>`)
