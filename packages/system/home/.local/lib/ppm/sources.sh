#!/usr/bin/env bash
# Source repositories: the source lists, cloning and updating, and the src/update/package commands
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

# Switch GitHub HTTPS entries in the user source list, and the origin remotes of cloned repos,
# to SSH. Only the user list is rewritten; system.list is ppm-managed and left alone.
# Usage: _src_ssh [alias]
_src_ssh() {
  local filter="${1:-}"
  local user_file
  user_file=$(_user_sources_file)
  collect_repos

  local i name url repo_dir remote changed found=false
  for i in "${!REPO_NAMES[@]}"; do
    name="${REPO_NAMES[$i]}"
    [[ -z "$filter" || "$name" == "$filter" ]] || continue
    found=true
    changed=false
    url="${REPO_URLS[$i]}"
    repo_dir="$PPM_DATA_HOME/$name"

    # Rewrite the list entry only when it lives in the user list
    if [[ "$url" == https://github.com/* ]] && [[ -f "$user_file" ]] &&
       awk -v u="$url" '$1 == u { found=1 } END { exit !found }' "$user_file"; then
      local tmp
      tmp=$(awk -v old="$url" -v new="$(_github_ssh_url "$url")" \
        '$1 == old { sub(/^[^[:space:]]+/, new) } { print }' "$user_file")
      printf '%s\n' "$tmp" > "$user_file"
      echo "$name: $(basename "$user_file") -> $(_github_ssh_url "$url")"
      changed=true
    fi

    if remote=$(git -C "$repo_dir" remote get-url origin 2>/dev/null) && [[ "$remote" == https://github.com/* ]]; then
      git -C "$repo_dir" remote set-url origin "$(_github_ssh_url "$remote")"
      echo "$name: origin -> $(_github_ssh_url "$remote")"
      changed=true
    fi

    $changed || echo "$name: already SSH"
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

    *)
      echo "Usage: ppm src <add|remove|list|ssh>"
      echo "  add [--top] <git-url> [alias]  Add a source repository"
      echo "  remove <url-or-alias>          Remove a source repository"
      echo "  list                           List configured sources"
      echo "  ssh [alias]                    Switch GitHub HTTPS sources and remotes to SSH"
      [[ -z "$subcommand" ]] || exit 1
      ;;
  esac
}

# Add a remote repo source and pull its contents
package() {
  if [[ $# -eq 0 ]]; then
    echo "Error: package requires a git URL"
    echo "Usage: ppm package <git-url>"
    exit 1
  fi

  local url="$1" user_ppm_url=https://github.com/maxcole/user-ppm.git
  local repo_name=$(basename "$url" .git)
  local repo_dir="$PPM_DATA_HOME/$repo_name"

  src add --top "$url"
  update

  if [[ ! -d "$repo_dir" ]]; then
    echo "Error: Failed to clone '$repo_name'"
    exit 1
  fi

  # Bootstrap with default packages from user-ppm
  rm -rf "$repo_dir/packages"
  git clone "$user_ppm_url" /tmp/user-ppm
  cp -a /tmp/user-ppm/packages "$repo_dir/"
  rm -rf /tmp/user-ppm

  # Copy user's current ppm config (the user source list, not the ppm-managed system.list)
  mkdir -p "$repo_dir/packages/ppm/home/.config/ppm"
  cp "$PPM_CONFIG_HOME/ppm.conf" "$(_user_sources_read)" "$repo_dir/packages/ppm/home/.config/ppm/" 2>/dev/null || true

  # Commit the initial packages
  git -C "$repo_dir" add packages
  git -C "$repo_dir" commit -m "add initial packages"

  # Install ppm package
  install -f "$repo_name/ppm"

  echo "Package source '$repo_name' ready. Don't forget to push the updates"
}

# Iterate over repos from the merged source lists and clone them to $PPM_DATA_HOME
update() {
  local filter="${1:-}"
  local all_updated=true

  collect_repos

  for i in "${!REPO_URLS[@]}"; do
    local repo_url="${REPO_URLS[$i]}"
    local repo_name="${REPO_NAMES[$i]}"

    # Skip local paths that aren't git URLs
    if ! is_git_url "$repo_url"; then
      continue
    fi

    # If a specific repo was requested, skip non-matching ones
    if [[ -n "$filter" && "$repo_name" != "$filter" ]]; then
      continue
    fi

    if [ ! -d $PPM_DATA_HOME/$repo_name ]; then
      echo "Cloning: $repo_url"
      git clone $repo_url $PPM_DATA_HOME/$repo_name
    else
      # Check for uncommitted changes or untracked files
      if ! git -C "$PPM_DATA_HOME/$repo_name" diff --quiet || \
         ! git -C "$PPM_DATA_HOME/$repo_name" diff --cached --quiet || \
         [[ -n $(git -C "$PPM_DATA_HOME/$repo_name" status --porcelain) ]]; then
        echo "Skipping $repo_name: has uncommitted changes. Please commit or stash them first."
        all_updated=false
        continue
      fi

      debug "Pulling latest for $repo_name"
      echo "Updating: $repo_name"
      git -C "$PPM_DATA_HOME/$repo_name" pull
    fi
  done

  $all_updated || return 1
}

# Auto-update repos if cache duration has elapsed
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
