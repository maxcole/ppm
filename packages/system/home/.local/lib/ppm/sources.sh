#!/usr/bin/env bash
# Source repositories: the source lists, cloning and updating, and the src and package commands
#
# Repos are read from two lists in priority order:
#   user.list   (yours; edited by `ppm src`) — highest priority
#   system.list (shipped by ppm/system) — the batteries-included defaults
# sources.list is the pre-split legacy name; if user.list is absent it is read as the user list.

# The user-managed source list `ppm src` edits. Migrates a plain legacy sources.list to
# user.list once (a symlinked legacy file — a config claimed into a repo — is left in place).
_user_sources_file() {
  if [[ ! -e "$PPM_USER_SOURCES" && -f "$PPM_LEGACY_SOURCES" && ! -L "$PPM_LEGACY_SOURCES" ]]; then
    mv "$PPM_LEGACY_SOURCES" "$PPM_USER_SOURCES"
  fi
  echo "$PPM_USER_SOURCES"
}

# The user list to READ from: user.list if present, else the legacy sources.list
_user_sources_read() {
  if [[ -f "$PPM_USER_SOURCES" ]]; then
    echo "$PPM_USER_SOURCES"
  elif [[ -f "$PPM_LEGACY_SOURCES" ]]; then
    echo "$PPM_LEGACY_SOURCES"
  fi
}

# Read the source lists into REPO_URLS and REPO_NAMES (array order is priority order).
# User entries come first, then system entries; an alias declared in both wins from the user
# list. Two-column format per line: URL alias (alias optional, defaults to basename).
collect_repos() {
  REPO_URLS=()
  REPO_NAMES=()

  local seen=" " file line url name
  for file in "$(_user_sources_read)" "$PPM_SYSTEM_SOURCES"; do
    [[ -n "$file" && -f "$file" ]] || continue
    while IFS= read -r line || [ -n "$line" ]; do
      # Skip empty lines and comments
      [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue

      read -r url name <<< "$line"
      [[ -z "$name" ]] && name="$(basename "$url" .git)"

      # Dedup by alias; the first occurrence (user list) wins
      [[ "$seen" == *" $name "* ]] && continue
      seen="$seen$name "

      REPO_URLS+=("$url")
      REPO_NAMES+=("$name")
      debug "Source: $url -> $name"
    done < "$file"
  done
}

# Check if argument is a known repo name (exists in PPM_DATA_HOME)
is_repo_name() {
  [[ -d "$PPM_DATA_HOME/$1/packages" ]]
}

# Check if entry is a git URL (not a local path)
is_git_url() {
  [[ "$1" == git@* || "$1" == *://* ]]
}

# Position of a repo in sources.list (lower is higher priority)
_repo_index() {
  local i
  for i in "${!REPO_NAMES[@]}"; do
    [[ "${REPO_NAMES[$i]}" == "$1" ]] && { echo "$i"; return; }
  done
  echo 9999
}

# Convert https://github.com/user/repo[.git] to git@github.com:user/repo[.git]
_github_ssh_url() {
  echo "git@github.com:${1#https://github.com/}"
}

# Rewrite a GitHub HTTPS entry to SSH in a specific list file. Returns 0 if the file
# contained the URL (and was rewritten), 1 otherwise.
_ssh_rewrite_in_file() {
  local file="$1" url="$2" tmp
  [[ -f "$file" ]] || return 1
  awk -v u="$url" '$1 == u { f=1 } END { exit !f }' "$file" || return 1
  tmp=$(awk -v old="$url" -v new="$(_github_ssh_url "$url")" \
    '$1 == old { sub(/^[^[:space:]]+/, new) } { print }' "$file")
  printf '%s\n' "$tmp" > "$file"
}

# Switch GitHub HTTPS source entries and the origin remotes of cloned repos to SSH.
# Writable lists: user.list always, and system.list only when you have protected it
# (`ppm file protect`); an unprotected https entry in system.list is reported, not changed.
# Usage: _src_ssh [alias]
_src_ssh() {
  local filter="${1:-}"
  local user_file
  user_file=$(_user_sources_file)

  # Lists src may write to, in priority order
  local writable=("$user_file") sys_rel="${PPM_SYSTEM_SOURCES#$HOME/}"
  _protected_has "$sys_rel" && writable+=("$PPM_SYSTEM_SOURCES")

  collect_repos

  local i name url repo_dir remote changed noted found=false f
  for i in "${!REPO_NAMES[@]}"; do
    name="${REPO_NAMES[$i]}"
    [[ -z "$filter" || "$name" == "$filter" ]] || continue
    found=true
    changed=false
    noted=false
    url="${REPO_URLS[$i]}"
    repo_dir="$PPM_DATA_HOME/$name"

    if [[ "$url" == https://github.com/* ]]; then
      # Rewrite the entry in the first writable list that contains it
      for f in ${writable[@]+"${writable[@]}"}; do
        if _ssh_rewrite_in_file "$f" "$url"; then
          echo "$name: $(basename "$f") -> $(_github_ssh_url "$url")"
          changed=true
          break
        fi
      done
      # https entry that only lives in an unprotected (ppm-managed) system.list
      if ! $changed && [[ -f "$PPM_SYSTEM_SOURCES" ]] &&
         awk -v u="$url" '$1 == u { f=1 } END { exit !f }' "$PPM_SYSTEM_SOURCES"; then
        echo "$name: https in system.list (ppm-managed); run 'ppm file protect ~/.config/ppm/system.list' to edit it here"
        noted=true
      fi
    fi

    if remote=$(git -C "$repo_dir" remote get-url origin 2>/dev/null) && [[ "$remote" == https://github.com/* ]]; then
      git -C "$repo_dir" remote set-url origin "$(_github_ssh_url "$remote")"
      echo "$name: origin -> $(_github_ssh_url "$remote")"
      changed=true
    fi

    { $changed || $noted; } || echo "$name: already SSH"
  done

  $found || { echo "Source not found: $filter"; return 1; }
}

# Print each entry of a source list file with its clone status (clean/dirty/missing)
_src_list_file() {
  local file="$1" line alias repo_dir status
  [[ -n "$file" && -f "$file" ]] || return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
    alias="${line##* }"
    repo_dir="$PPM_DATA_HOME/$alias"
    status="missing"
    if [[ -d "$repo_dir/.git" ]]; then
      if [[ -z "$(git -C "$repo_dir" status --porcelain 2>/dev/null)" ]]; then
        status="clean"
      else
        status="dirty"
      fi
    fi
    printf "%s  %s\n" "$line" "$status"
  done < "$file"
}

# Manage sources in the user list (add/remove/ssh); list shows both user and system
src() {
  local subcommand="${1:-}"
  shift 2>/dev/null || true

  case "$subcommand" in
    add)
      local top=false
      [[ "${1:-}" == "--top" ]] && { top=true; shift; }

      if [[ $# -eq 0 ]]; then
        echo "Error: src add requires a git URL"
        echo "Usage: ppm src add [--top] <git-url> [alias]"
        exit 1
      fi

      local url="$1"

      # Create config directory if it doesn't exist
      mkdir -p "$PPM_CONFIG_HOME"

      # src always edits the user list (never system.list)
      local user_file
      user_file=$(_user_sources_file)
      touch "$user_file"

      local alias="${2:-$(basename "$url" .git)}"
      local entry="$url  $alias"

      # Check if URL already exists in the user list (match first column)
      if awk '{print $1}' "$user_file" 2>/dev/null | grep -qxF "$url"; then
        echo "Source already exists: $url"
        return 0
      fi

      # Add entry to the user list
      if $top; then
        local tmp=$(mktemp)
        echo "$entry" > "$tmp"
        cat "$user_file" >> "$tmp"
        mv "$tmp" "$user_file"
      else
        echo "$entry" >> "$user_file"
      fi
      echo "Added source: $url ($alias)"
      ;;

    remove)
      if [[ $# -eq 0 ]]; then
        echo "Error: src remove requires a URL or alias"
        echo "Usage: ppm src remove <url-or-alias>"
        exit 1
      fi

      local target="$1"
      local removed=false
      local user_file
      user_file=$(_user_sources_file)

      # Match on either URL (first column) or alias (second column) in the user list.
      # Use awk instead of sed to avoid delimiter conflicts with URLs containing /
      if [[ -f "$user_file" ]] &&
         awk -v t="$target" '$1 == t || $NF == t { found=1 } END { exit !found }' "$user_file" 2>/dev/null; then
        local tmp
        tmp=$(awk -v t="$target" '$1 != t && $NF != t' "$user_file")
        if [[ -n "$tmp" ]]; then
          printf '%s\n' "$tmp" > "$user_file"
        else
          : > "$user_file"
        fi
        removed=true
      fi

      if $removed; then
        echo "Removed source: $target"
      else
        echo "Source not found in user list: $target (system.list is ppm-managed)"
        return 1
      fi
      ;;

    list)
      local user_file
      user_file=$(_user_sources_read)
      if [[ -z "$user_file" && ! -f "$PPM_SYSTEM_SOURCES" ]]; then
        echo "No sources configured"
      else
        echo "# user ($(basename "${user_file:-$PPM_USER_SOURCES}"))"
        _src_list_file "$user_file"
        echo "# system ($(basename "$PPM_SYSTEM_SOURCES"))"
        _src_list_file "$PPM_SYSTEM_SOURCES"
      fi
      ;;

    ssh)
      _src_ssh "$@"
      ;;

    update)
      _src_update "$@"
      ;;

    *)
      echo "Usage: ppm src <add|remove|list|ssh|update>"
      echo "  add [--top] <git-url> [alias]  Add a source repository"
      echo "  remove <url-or-alias>          Remove a source repository"
      echo "  list                           List configured sources"
      echo "  ssh [alias]                    Switch GitHub HTTPS sources and remotes to SSH"
      echo "  update [alias...]              Clone missing and pull existing source repositories"
      [[ -z "$subcommand" ]] || exit 1
      ;;
  esac
}

# `ppm customize`: start customizing this machine. Creates a local git repo as the "user"
# source with a system package (a layer of ppm/system) that holds user.list, and stows it — so
# from here your source list lives in your own repo. Dispatched through main(): it calls install.
customize() {
  local alias="$PPM_USER_REPO_ALIAS"
  local repo_dir="$PPM_DATA_HOME/$alias"
  local config_dir="$repo_dir/packages/system/home/.config/ppm"
  local user_file

  collect_repos
  if [[ " ${REPO_NAMES[*]:-} " == *" $alias "* ]]; then
    echo "Error: a '$alias' source already exists; this machine is already customized"
    return 1
  fi
  if [[ -e "$repo_dir" ]]; then
    echo "Error: $repo_dir already exists"
    return 1
  fi
  if [[ -L "$PPM_USER_SOURCES" ]]; then
    echo "Error: $PPM_USER_SOURCES is already a link into a package ($(readlink "$PPM_USER_SOURCES"))"
    return 1
  fi
  if _protected_has "${PPM_USER_SOURCES#$HOME/}"; then
    echo "Error: $PPM_USER_SOURCES is protected; run 'ppm file unprotect' on it first"
    return 1
  fi

  # The repo, with a system package that will own user.list
  mkdir -p "$config_dir"
  git -C "$repo_dir" init -q
  printf 'version: 0.1.0\nauthor: %s\n' "${USER:-unknown}" > "$repo_dir/packages/system/package.yml"

  # Register the repo at the top of the user list. A local path: it is never pulled until you
  # give it a remote. The repo's copy of the list must list the repo itself, or once it is
  # stowed nothing registers "user" and the repo drops out of the sources.
  src add --top "$repo_dir" "$alias"
  user_file=$(_user_sources_file)
  cp "$user_file" "$config_dir/user.list"

  # -f swaps the plain user.list for a link into the repo (same content). Only the user layer:
  # it is the top layer so it can't conflict, and -f stays away from ppm/system.
  force=true install "$alias/system"

  echo ""
  echo "ppm is now customizable from $repo_dir (source '$alias', highest priority)."
  echo "  - $PPM_USER_SOURCES lives in that repo now; commit it"
  echo "  - take over any ppm-managed file with: ppm file claim <file>"
  echo "  - to use it on other machines: add a remote and push, change the '$alias' line in"
  echo "    user.list to that git URL, then on a new machine run: install.sh --repo <git-url>"
}

# --- Per-repo update times: $PPM_CACHE_HOME/updated/<alias> holds the epoch of the repo's last
# successful clone or pull. Tracking each repo separately means one repo that is skipped (local
# changes) stays stale on its own instead of making every install pull all the others again.

_repo_updated_file() {
  echo "$PPM_CACHE_HOME/updated/$1"
}

# Record that a repo was just cloned or pulled
_repo_mark_updated() {
  mkdir -p "$PPM_CACHE_HOME/updated"
  date +%s > "$(_repo_updated_file "$1")"
}

# True when a repo has never been updated, or not within PPM_UPDATE_CACHE_DURATION seconds
_repo_stale() {
  local file last duration="${PPM_UPDATE_CACHE_DURATION:-86400}"
  file=$(_repo_updated_file "$1")
  [[ -f "$file" ]] || return 0
  last=$(cat "$file" 2>/dev/null)
  [[ "$last" =~ ^[0-9]+$ ]] || return 0
  (( $(date +%s) - last > duration ))
}

# `ppm src update [alias...]`: clone missing and pull existing repos from the merged source lists
# into $PPM_DATA_HOME — all of them, or only the named aliases. Each successful clone/pull records
# that repo's update time. Repos with uncommitted changes are skipped and left stale, so they are
# checked again next time. Returns 1 if any repo was skipped or failed.
# --auto (used by update_ppm_if_needed): report skipped repos in one summary line instead of one
# per repo, since install repeats it on every run while a repo has changes; set
# PPM_QUIET_SKIPPED_REPOS=true in ppm.conf to show it only with --debug.
_src_update() {
  local auto=false
  [[ "${1:-}" == "--auto" ]] && { auto=true; shift; }
  local wanted=" $* " all_updated=true i repo_url repo_name dir skipped=()

  collect_repos

  for i in "${!REPO_URLS[@]}"; do
    repo_url="${REPO_URLS[$i]}"
    repo_name="${REPO_NAMES[$i]}"
    dir="$PPM_DATA_HOME/$repo_name"

    # Local paths are never cloned or pulled
    is_git_url "$repo_url" || continue
    # When aliases are named, only those
    [[ $# -eq 0 || "$wanted" == *" $repo_name "* ]] || continue

    if [[ ! -d "$dir" ]]; then
      echo "Cloning: $repo_url"
      if git clone "$repo_url" "$dir"; then
        _repo_mark_updated "$repo_name"
      else
        all_updated=false
      fi
      continue
    fi

    # Uncommitted changes or untracked files: skip, leaving the repo stale
    if ! git -C "$dir" diff --quiet || ! git -C "$dir" diff --cached --quiet ||
       [[ -n $(git -C "$dir" status --porcelain) ]]; then
      if $auto; then
        skipped+=("$repo_name")   # reported once, below
      else
        echo "Skipping $repo_name: has uncommitted changes. Please commit or stash them first."
      fi
      all_updated=false
      continue
    fi

    echo "Updating: $repo_name"
    if git -C "$dir" pull; then
      _repo_mark_updated "$repo_name"
    else
      all_updated=false
    fi
  done

  # During install, one line for all skipped repos; PPM_QUIET_SKIPPED_REPOS=true (ppm.conf)
  # moves it to --debug output
  if [[ ${#skipped[@]} -gt 0 ]]; then
    local list
    printf -v list '%s, ' "${skipped[@]}"
    if [[ "${PPM_QUIET_SKIPPED_REPOS:-false}" == true ]]; then
      debug "Not updated (uncommitted changes): ${list%, }"
    else
      echo "Not updated (uncommitted changes): ${list%, }"
    fi
  fi

  $all_updated
}

# Auto-update (run by install): pull only the repos that are stale — never updated, or not within
# PPM_UPDATE_CACHE_DURATION seconds. Fresh repos aren't touched.
update_ppm_if_needed() {
  local stale=() i
  collect_repos
  for i in "${!REPO_NAMES[@]}"; do
    is_git_url "${REPO_URLS[$i]}" || continue
    if _repo_stale "${REPO_NAMES[$i]}"; then
      stale+=("${REPO_NAMES[$i]}")
    fi
  done

  [[ ${#stale[@]} -gt 0 ]] || return 0
  debug "Stale repos: ${stale[*]}"
  _src_update --auto "${stale[@]}" || debug "Some repos were not updated; they stay stale"
}
