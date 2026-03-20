---
---

# Plan 04 — Package.yml Migration

## Context — read these files first

- `~/.local/share/ppm/pde-ppm/packages/*/install.sh` — active `dependencies()` patterns
- `~/.local/share/ppm/pdt-ppm/packages/*/install.sh` — more patterns
- `~/.local/share/ppm/rjayroach-ppm/packages/*/install.sh` — includes commented-out `dependencies()`
- `~/.local/share/ppm/ppm/packages/*/install.sh` — ppm repo packages

## Overview

One-shot migration script that creates `package.yml` for every package across all repos in `~/.local/share/ppm/`, extracts dependencies from `install.sh`, and removes the `dependencies()` function from the shell scripts.

The script operates on the cloned repos in `$PPM_DATA_HOME` (`~/.local/share/ppm/`). After running, the changes should be committed in each repo.

## Implementation

### Migration script: `scripts/migrate-metadata.sh`

Create this script at the ppm repo root. It is disposable — run once, commit results, delete.

```bash
#!/usr/bin/env bash
set -euo pipefail

PPM_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}/ppm"
AUTHOR="rjayroach"

for repo_dir in "$PPM_DATA_HOME"/*/packages; do
  [[ -d "$repo_dir" ]] || continue
  repo_name="$(basename "$(dirname "$repo_dir")")"

  for pkg_dir in "$repo_dir"/*/; do
    [[ -d "$pkg_dir" ]] || continue
    pkg_name="$(basename "$pkg_dir")"
    install_file="$pkg_dir/install.sh"
    meta_file="$pkg_dir/package.yml"

    # Skip if package.yml already exists
    [[ -f "$meta_file" ]] && continue

    echo "Processing: $repo_name/$pkg_name"
    deps=""

    if [[ -f "$install_file" ]]; then
      deps=$(extract_and_remove_deps "$install_file")
    fi

    create_package_yml "$meta_file" "$deps"
  done
done
```

### Key functions in the script:

#### `extract_and_remove_deps()`

1. **Detect commented-out `dependencies()`**: Look for a block matching the pattern:
   ```
   # dependencies() {
   #   echo "..."
   # }
   ```
   The comment prefix may be `# ` or `#` (with or without trailing space). The function block may be multi-line.

2. **If commented out**: Uncomment the block in-place first (strip leading `# ` or `#` from each line of the function).

3. **Source the file in a subshell** and capture `dependencies` output:
   ```bash
   deps=$(bash -c 'source "$1" 2>/dev/null; type dependencies &>/dev/null && dependencies' -- "$install_file")
   ```

4. **Remove the `dependencies()` function block** from the file. The block starts at `dependencies()` (or `dependencies ()`) and ends at the next `}` that's at the start of a line (possibly with leading whitespace). Also remove any blank lines immediately following the removed block.

5. If the file is left with only comments and blank lines (no actual functions), leave it — other hooks like `post_install()` etc. may be added later.

#### `create_package_yml()`

Use `yq` to create the file:

```bash
create_package_yml() {
  local meta_file="$1" deps="$2"

  if [[ -n "$deps" ]]; then
    # Build depends array
    local dep_yaml=""
    for dep in $deps; do
      dep_yaml="${dep_yaml}  - ${dep}\n"
    done
    printf "version: 0.1.0\nauthor: %s\ndepends:\n%b" "$AUTHOR" "$dep_yaml" > "$meta_file"
  else
    printf "version: 0.1.0\nauthor: %s\n" "$AUTHOR" > "$meta_file"
  fi
}
```

Note: using printf rather than yq for creation since the structure is trivial and deterministic. yq can be used for validation after if desired.

### Edge cases to handle

1. **Commented-out deps with inline comments after echo**: e.g., `echo "chorus gems network podman tailscale" # ansible opentofu"` — the deps extraction should only capture stdout, so inline bash comments don't matter (bash strips them). But the commented-out-function detection needs to handle this pattern.

2. **Partially commented deps**: e.g., one dep commented out within the echo string (like `echo "chorus gems" # network`). This is a bash comment inside the function — `source` handles it correctly. Just extract what `dependencies` actually returns.

3. **No `install.sh` at all**: Some packages are home-only (just stow configs). Still create `package.yml` with version and author, no depends.

4. **Multiple repos with same package name**: Each gets its own `package.yml` independently.

## Test Spec

Before running, snapshot the current state:
```bash
find ~/.local/share/ppm/*/packages -name "install.sh" -exec grep -l "dependencies" {} \;
```

After running:
- Every package dir has a `package.yml`
- No `install.sh` contains a `dependencies()` function (active or commented)
- `package.yml` files have correct `depends` matching what the old function returned
- `install.sh` files retain all other functions (`post_install`, `install_macos`, etc.)

## Verification

- [ ] `find ~/.local/share/ppm/*/packages -name "package.yml" | wc -l` equals total package count
- [ ] `grep -r "dependencies()" ~/.local/share/ppm/*/packages/*/install.sh` returns nothing
- [ ] Spot-check: `pde-ppm/claude/package.yml` has `depends: [mise]`
- [ ] Spot-check: `pde-ppm/rails/package.yml` has `depends: [ruby]`
- [ ] Spot-check: `rjayroach-ppm/rjayroach/package.yml` has `depends: [chorus, gems]` (was commented out)
- [ ] Spot-check: `pde-ppm/mise/package.yml` has `depends: [zsh]` (was commented out)
- [ ] Spot-check: `pde-ppm/tmux/package.yml` has no `depends` key (no dependencies function)
- [ ] All `install.sh` files still parse correctly: `bash -n <file>` passes for each
