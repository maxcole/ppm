#!/usr/bin/env bash
# Source repositories: sources.list, cloning and updating, and the src/update/package commands

# Read sources.list into REPO_URLS and REPO_NAMES (source order is priority order)
# Supports two-column format: URL alias (alias is optional, defaults to basename)
collect_repos() {
  REPO_URLS=()
  REPO_NAMES=()

  while IFS= read -r line || [ -n "$line" ]; do
    # Skip empty lines and comments
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue

    local url name
    read -r url name <<< "$line"
    [[ -z "$name" ]] && name="$(basename "$url" .git)"

    REPO_URLS+=("$url")
    REPO_NAMES+=("$name")
    debug "Source: $url -> $name"
  done < "$PPM_SOURCES_FILE"
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

# Switch GitHub HTTPS entries in sources.list, and the origin remotes of cloned repos, to SSH
# Usage: _src_ssh [alias]
_src_ssh() {
  local filter="${1:-}"
  [[ -f "$PPM_SOURCES_FILE" ]] || { echo "No sources configured"; return 1; }
  collect_repos

  local i name url repo_dir remote changed found=false
  for i in "${!REPO_NAMES[@]}"; do
    name="${REPO_NAMES[$i]}"
    [[ -z "$filter" || "$name" == "$filter" ]] || continue
    found=true
    changed=false
    url="${REPO_URLS[$i]}"
    repo_dir="$PPM_DATA_HOME/$name"

    if [[ "$url" == https://github.com/* ]]; then
      local tmp
      tmp=$(awk -v old="$url" -v new="$(_github_ssh_url "$url")" \
        '$1 == old { sub(/^[^[:space:]]+/, new) } { print }' "$PPM_SOURCES_FILE")
      printf '%s\n' "$tmp" > "$PPM_SOURCES_FILE"
      echo "$name: sources.list -> $(_github_ssh_url "$url")"
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

# Manage sources in sources.list
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

      # Create sources.list if it doesn't exist
      touch "$PPM_SOURCES_FILE"

      local alias="${2:-$(basename "$url" .git)}"
      local entry="$url  $alias"

      # Check if URL already exists in sources.list (match first column)
      if awk '{print $1}' "$PPM_SOURCES_FILE" 2>/dev/null | grep -qxF "$url"; then
        echo "Source already exists: $url"
        return 0
      fi

      # Add entry to sources.list
      if $top; then
        local tmp=$(mktemp)
        echo "$entry" > "$tmp"
        cat "$PPM_SOURCES_FILE" >> "$tmp"
        mv "$tmp" "$PPM_SOURCES_FILE"
      else
        echo "$entry" >> "$PPM_SOURCES_FILE"
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

      # Match on either URL (first column) or alias (second column)
      # Use awk instead of sed to avoid delimiter conflicts with URLs containing /
      if awk -v t="$target" '$1 == t || $NF == t { found=1 } END { exit !found }' "$PPM_SOURCES_FILE" 2>/dev/null; then
        local tmp
        tmp=$(awk -v t="$target" '$1 != t && $NF != t' "$PPM_SOURCES_FILE")
        if [[ -n "$tmp" ]]; then
          printf '%s\n' "$tmp" > "$PPM_SOURCES_FILE"
        else
          : > "$PPM_SOURCES_FILE"
        fi
        removed=true
      fi

      if $removed; then
        echo "Removed source: $target"
      else
        echo "Source not found: $target"
        return 1
      fi
      ;;

    list)
      if [[ -f "$PPM_SOURCES_FILE" ]]; then
        while IFS= read -r line || [[ -n "$line" ]]; do
          [[ -z "$line" ]] && continue
          local alias="${line##* }"
          local repo_dir="$PPM_DATA_HOME/$alias"
          local status="missing"
          if [[ -d "$repo_dir/.git" ]]; then
            if [[ -z "$(git -C "$repo_dir" status --porcelain 2>/dev/null)" ]]; then
              status="clean"
            else
              status="dirty"
            fi
          fi
          printf "%s  %s\n" "$line" "$status"
        done < "$PPM_SOURCES_FILE"
      else
        echo "No sources configured"
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

  # Copy user's current ppm config
  mkdir -p "$repo_dir/packages/ppm/home/.config/ppm"
  cp "$PPM_CONFIG_HOME/ppm.conf" "$PPM_CONFIG_HOME/sources.list" "$repo_dir/packages/ppm/home/.config/ppm/" 2>/dev/null || true

  # Commit the initial packages
  git -C "$repo_dir" add packages
  git -C "$repo_dir" commit -m "add initial packages"

  # Install ppm package
  install -f "$repo_name/ppm"

  echo "Package source '$repo_name' ready. Don't forget to push the updates"
}

# Iterate over repos listed in $PPM_SOURCES_FILE and clone them to $PPM_DATA_HOME
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
