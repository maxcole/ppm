---
---

# Plan 03 — Update Timer, Debug Logging & User Messages

## Context — read these files first

- `ppm` — entrypoint, `main()`, flag parsing, `update()`
- `lib/brew.sh` — `update_brew_if_needed()` pattern (the timer model to replicate)
- `~/.config/ppm/ppm.conf` — config variables

## Overview

Three related concerns that touch the ppm runtime:

1. **PPM update timer** — mirror the brew cache-duration pattern: on any `ppm install`, check if `ppm update` should run first, based on a configurable interval.
2. **Debug logging** — `--debug` flag enables verbose output throughout ppm. Packages can also call a `debug` function.
3. **User messages** — packages call `user_message "text"` during install. Messages are collected and displayed at the end of the run, then the temp file is cleaned up.

## Implementation

### 1. PPM update timer

Add to `ppm.conf`:
```bash
# Duration in seconds between ppm repo updates (default: 24 hours)
PPM_UPDATE_CACHE_DURATION=86400
```

Add `update_ppm_if_needed()` to `lib/repo.sh`, following the same pattern as `update_brew_if_needed()`:

```bash
update_ppm_if_needed() {
  local cache_duration="${PPM_UPDATE_CACHE_DURATION:-86400}"
  local cache_file="$PPM_CACHE_HOME/ppm_last_update"

  if [[ ! -f "$cache_file" ]] || [[ $(($(date +%s) - $(cat "$cache_file"))) -gt $cache_duration ]]; then
    [[ ! -d "$PPM_CACHE_HOME" ]] && mkdir -p "$PPM_CACHE_HOME"
    update  # calls the existing update function (git pull on all repos)
    date +%s > "$cache_file"
  fi
}
```

Call `update_ppm_if_needed` at the start of `install()`, alongside the existing `update_brew_if_needed` call.

### 2. Debug logging

Add a global `PPM_DEBUG` variable, set by the `--debug` flag in `main()`:

```bash
PPM_DEBUG=false
```

And in flag parsing:
```bash
--debug) PPM_DEBUG=true ;;
```

Add a `debug()` function to `lib/core.sh`:

```bash
debug() {
  $PPM_DEBUG && echo -e "[DEBUG] $*" >&2
}
```

This writes to stderr so it doesn't interfere with stdout output (e.g., `ppm path` which outputs a path that might be captured). Packages can call `debug "message"` from their `install.sh` since it's sourced in a subshell that inherits the function.

Sprinkle `debug` calls in key places:
- `installer()` — entering package, resolving deps, stowing
- `update()` — cloning/pulling each repo
- `collect_repos()` — repos found
- `stow_subdir()` — what's being stowed

### 3. User messages

Add to `lib/core.sh`:

```bash
# Temp file for collecting user messages across packages
PPM_MSG_FILE=$(mktemp /tmp/ppm-messages.XXXXXX)

user_message() {
  echo "$*" >> "$PPM_MSG_FILE"
}

# Called at the end of a ppm run to display collected messages
flush_user_messages() {
  if [[ -s "$PPM_MSG_FILE" ]]; then
    echo ""
    echo "=== Package Messages ==="
    cat "$PPM_MSG_FILE"
    echo "========================"
  fi
  rm -f "$PPM_MSG_FILE"
}
```

Call `flush_user_messages` at the end of `install()` and `remove()`.

Packages use it like:
```bash
post_install() {
  user_message "op: Open 1Password desktop and enable CLI integration in Developer settings"
}
```

The temp file approach works because even though `install.sh` is sourced in subshells, those subshells inherit `PPM_MSG_FILE` and can write to it (file writes go to the shared temp file, not to a subshell-local copy).

### 4. Export `PPM_DEBUG` for subshells

Since `install.sh` scripts are sourced in subshells `(source ...)`, the `PPM_DEBUG` variable and `debug` function need to be available. Variables set with `set -a` are auto-exported. For functions, bash subshells created with `( ... )` already inherit functions from the parent shell, so `debug` and `user_message` are available without explicit export.

## Test Spec

Manual verification:
- Set `PPM_UPDATE_CACHE_DURATION=5` in ppm.conf, run `ppm install zsh`, verify repos update. Wait 6 seconds, run again, verify update runs again. Set back to 86400.
- `ppm install --debug zsh` produces `[DEBUG]` lines on stderr
- Add `user_message "test message"` to a package's `post_install`, run install, verify message appears at end
- Normal (non-debug) output is unchanged

## Verification

- [ ] `PPM_UPDATE_CACHE_DURATION` is read from ppm.conf
- [ ] `$PPM_CACHE_HOME/ppm_last_update` file is created/updated on `ppm install`
- [ ] `--debug` flag is parsed in `main()` and sets `PPM_DEBUG=true`
- [ ] `debug()` function exists in `lib/core.sh` and writes to stderr
- [ ] `user_message()` and `flush_user_messages()` exist in `lib/core.sh`
- [ ] Messages from multiple packages aggregate correctly
- [ ] Temp file is cleaned up after `flush_user_messages`
