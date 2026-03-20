
# Plan 04a — Post-Migration Fixes

## Context — read these files first

- `lib/core.sh` — `debug()`, `user_message()`, `flush_user_messages()`, `PPM_MSG_FILE`
- `lib/brew.sh` — `update_brew_if_needed()`, `install_dep()`
- `lib/repo.sh` — `update_ppm_if_needed()`
- `ppm` — `update()` function, `install()` entry point, `installer()` per-package loop
- `~/.local/share/ppm/pdt-ppm/packages/solana/install.sh` — example of current `exit 1` pattern in `install_linux()`

## Overview

Six targeted fixes to issues identified after plans 01–04:

1. `update_ppm_if_needed()` should not update the cache timer if any repo failed to update (e.g., dirty repo skipped)
2. Move `install_dep()` from `brew.sh` to `core.sh` (it handles both apt and brew); rename `brew.sh` to `update.sh` (contains only `update_brew_if_needed` and `update_ppm_if_needed`)
3. `user_message()` should auto-prepend the calling package name for context
4. `flush_user_messages()` should interpret embedded `\n` as actual line breaks
5. Add an EXIT trap to clean up the `PPM_MSG_FILE` temp file on any exit (error, signal, normal)
6. Add `ppm_fail()` function for packages to signal install failures with context

## Implementation

### 1. Update timer — conditional on full success

Modify `update()` to track whether all repos updated successfully. Currently, repos with dirty state print "Skipping..." and `continue`. The function needs to signal back to `update_ppm_if_needed()` that not all repos succeeded.

Approach: have `update()` return non-zero if any repo was skipped.

```bash
# In update() — add a tracking variable at the top:
local all_updated=true

# Where it currently says:
#   echo "Skipping $repo_name: has uncommitted changes..."
#   continue
# Add before continue:
all_updated=false

# At the end of update(), add:
$all_updated || return 1
```

Then in `update_ppm_if_needed()` in `lib/repo.sh` (will become `lib/update.sh`):

```bash
update_ppm_if_needed() {
  local cache_duration="${PPM_UPDATE_CACHE_DURATION:-86400}"
  local cache_file="$PPM_CACHE_HOME/ppm_last_update"

  if [[ ! -f "$cache_file" ]] || [[ $(($(date +%s) - $(cat "$cache_file"))) -gt $cache_duration ]]; then
    [[ ! -d "$PPM_CACHE_HOME" ]] && mkdir -p "$PPM_CACHE_HOME"
    debug "PPM repos stale, running update"
    if update; then
      date +%s > "$cache_file"
    else
      debug "PPM update incomplete, timer not reset"
    fi
  fi
}
```

Note: `update()` is called from `install()` via `update_ppm_if_needed()`. Since `set -euo pipefail` is in effect, we need to make sure the non-zero return from `update()` doesn't cause ppm to exit. The `if update; then` construct handles this — it tests the return code without triggering `set -e`.

### 2. Move `install_dep` to `core.sh`, rename `brew.sh` → `update.sh`

**Move `install_dep()`** from `lib/brew.sh` to `lib/core.sh`. Place it after the `os()` function since it depends on it.

**Move `update_ppm_if_needed()`** from `lib/repo.sh` to `lib/brew.sh`.

**Rename `lib/brew.sh`** to `lib/update.sh`. It now contains only:
- `update_brew_if_needed()`
- `update_ppm_if_needed()`

Both are periodic-update-timer functions — the file name reflects the shared concern.

**Delete `lib/brew.sh`** after the rename (or just `mv`).

### 3. `user_message` — auto-prepend package name

Add a `PPM_CURRENT_PACKAGE` variable that `installer()` sets before processing each package. `user_message()` reads it to prepend context.

In `lib/core.sh`:

```bash
# Set by installer() before sourcing each package's install.sh
PPM_CURRENT_PACKAGE=""

user_message() {
  local prefix=""
  [[ -n "$PPM_CURRENT_PACKAGE" ]] && prefix="[$PPM_CURRENT_PACKAGE] "
  echo "${prefix}$*" >> "$PPM_MSG_FILE"
}
```

In `ppm`'s `installer()`, set the variable at the start of each package's processing block (before any subshell that sources `install.sh`):

```bash
PPM_CURRENT_PACKAGE="$repo_name/$package_name"
```

Since `install.sh` hooks run in subshells `( source ... )`, they inherit `PPM_CURRENT_PACKAGE` from the parent. The variable is readable but any subshell modification doesn't leak back — which is exactly what we want.

Example output:
```
=== Package Messages ===
[pde-ppm/op] Open 1Password desktop and enable CLI integration
  in Developer settings
[pde-ppm/nvim] Run :checkhealth after first launch
========================
```

### 4. `flush_user_messages` — interpret `\n`

Replace the `cat` in `flush_user_messages()` with a read loop that interprets escape sequences:

```bash
flush_user_messages() {
  if [[ -s "$PPM_MSG_FILE" ]]; then
    echo ""
    echo "=== Package Messages ==="
    while IFS= read -r line; do
      printf '%b\n' "$line"
    done < "$PPM_MSG_FILE"
    echo "========================"
  fi
  rm -f "$PPM_MSG_FILE"
}
```

`printf '%b'` interprets backslash escape sequences (`\n`, `\t`, etc.) in the argument. So a package calling:
```bash
user_message "Step 1: Open settings\nStep 2: Enable CLI"
```

Would render as:
```
[pde-ppm/op] Step 1: Open settings
Step 2: Enable CLI
```

### 5. EXIT trap for temp file cleanup

Add near the top of `lib/core.sh`, right after `PPM_MSG_FILE` is defined:

```bash
PPM_MSG_FILE=$(mktemp /tmp/ppm-messages.XXXXXX)
trap 'rm -f "$PPM_MSG_FILE"' EXIT
```

The `EXIT` trap fires on:
- Normal exit (exit 0)
- Error exit (set -e triggered, explicit exit 1)
- Signals (SIGINT/ctrl-c, SIGTERM)

This means `flush_user_messages` no longer needs to `rm -f` the file — the trap handles it. But it's harmless to leave the `rm` in flush as a belt-and-suspenders approach; `rm -f` on a missing file is a no-op.

### 6. `ppm_fail()` — structured failure for packages

Add to `lib/core.sh`:

```bash
# Called by packages to signal a non-fatal install failure.
# Logs the error immediately to stderr and queues it for end-of-run display.
# The calling function should `return` after calling ppm_fail.
# Usage (in a package install.sh):
#   ppm_fail "No pre-built binaries for arm64 Linux"
#   return
ppm_fail() {
  local prefix=""
  [[ -n "$PPM_CURRENT_PACKAGE" ]] && prefix="[$PPM_CURRENT_PACKAGE] "
  echo -e "${prefix}ERROR: $*" >&2
  user_message "ERROR: $*"
  return 1
}
```

Behavior:
- Prints the error immediately to stderr (visible in real-time during install)
- Queues the error into `PPM_MSG_FILE` via `user_message` (so it also appears in the end-of-run summary with package context)
- Returns non-zero so the caller can bail out of the current hook

Packages use it like:

```bash
# In pdt-ppm/solana/install.sh — replace the current exit 1 pattern:
install_linux() {
  if [[ "$(arch)" == "arm64" ]]; then
    ppm_fail "No pre-built binaries for arm64 Linux.\nValid targets: x86_64-unknown-linux-gnu, x86_64-apple-darwin, aarch64-apple-darwin.\nBuild from source via cargo instead."
    return
  fi
}
```

Since `install_linux()` runs inside a `( source ... )` subshell in `installer()`, the `return` exits the function, the subshell completes with non-zero, and ppm continues to the next package. The error is both visible immediately and aggregated at the end.

**Update `pdt-ppm/solana/install.sh`** to use `ppm_fail` + `return` instead of `echo` + `exit 1`.

## Test Spec

### Timer test
1. Make one of the repos dirty (touch a file, don't commit)
2. Delete `~/.cache/ppm/ppm_last_update` to force a stale check
3. Run `ppm install --debug zsh`
4. Verify "PPM update incomplete, timer not reset" appears in debug output
5. Verify `~/.cache/ppm/ppm_last_update` was NOT created/updated
6. Clean up the dirty repo, run again — verify the timer file IS written

### install_dep location test
1. `grep -r 'install_dep' lib/` — should only appear in `core.sh`
2. Verify `lib/update.sh` exists, `lib/brew.sh` does not
3. `ppm install tmux` — `install_dep` still works (called from install.sh hooks)

### user_message package context test
1. Temporarily add to any package's `post_install`:
   ```bash
   user_message "Remember to configure this manually"
   ```
2. Run `ppm install <that-package>`
3. Verify output shows `[repo/package] Remember to configure this manually`

### user_message newline test
1. Temporarily add to any package's `post_install`:
   ```bash
   user_message "Line one\nLine two\nLine three"
   ```
2. Run `ppm install <that-package>`
3. Verify output shows three separate lines under "Package Messages", first line prefixed with package name

### Trap test
1. Run `ppm install` and ctrl-c mid-way
2. Verify no `/tmp/ppm-messages.*` files linger
3. `ls /tmp/ppm-messages.* 2>/dev/null` should return nothing

### ppm_fail test
1. On a non-arm64 machine, temporarily modify a package's hook to call:
   ```bash
   ppm_fail "Test failure message\nWith a second line"
   return
   ```
2. Run `ppm install <that-package>`
3. Verify: error appears immediately on stderr during install
4. Verify: error appears in end-of-run "Package Messages" with package prefix
5. Verify: ppm continues installing subsequent packages (doesn't abort)
6. On pdt-ppm/solana specifically: verify the old `echo ... ; exit 1` pattern is replaced with `ppm_fail ... ; return`

## Verification

- [ ] `update()` returns non-zero when any repo is skipped
- [ ] `update_ppm_if_needed()` does not write cache file on partial update
- [ ] `install_dep()` is in `lib/core.sh`
- [ ] `lib/update.sh` exists with `update_brew_if_needed` and `update_ppm_if_needed`
- [ ] `lib/brew.sh` does not exist
- [ ] `PPM_CURRENT_PACKAGE` is set in `installer()` before each package
- [ ] `user_message()` prepends `[$PPM_CURRENT_PACKAGE]` when the variable is set
- [ ] `flush_user_messages` uses `printf '%b\n'` instead of `cat`
- [ ] `trap 'rm -f "$PPM_MSG_FILE"' EXIT` is present in `lib/core.sh`
- [ ] `ppm_fail()` exists in `lib/core.sh`, prints to stderr and calls `user_message`
- [ ] `pdt-ppm/solana/install.sh` uses `ppm_fail` + `return` instead of `echo` + `exit 1`
- [ ] All existing ppm commands still work
