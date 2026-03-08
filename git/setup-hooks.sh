#!/usr/bin/env bash
# Setup ppm git hooks in a package repository
# Usage: setup-hooks.sh [repo_dir]
#   repo_dir defaults to current directory
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="${1:-.}"
REPO_DIR="$(cd "$REPO_DIR" && pwd)"

if [[ ! -d "$REPO_DIR/.git" ]]; then
  echo "Error: $REPO_DIR is not a git repository"
  exit 1
fi

HOOKS_DIR="$REPO_DIR/.git/hooks"
HOOKS_SRC="$SCRIPT_DIR/hooks"

# Copy hook library into the repo's hooks dir
mkdir -p "$HOOKS_DIR/lib"
cp "$HOOKS_SRC/lib/package-meta.sh" "$HOOKS_DIR/lib/package-meta.sh"

# Symlink pre-commit hook
ln -sf "$HOOKS_SRC/pre-commit" "$HOOKS_DIR/pre-commit"
chmod +x "$HOOKS_DIR/pre-commit"

echo "Hooks installed for $(basename "$REPO_DIR")"
