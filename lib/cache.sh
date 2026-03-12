#!/usr/bin/env bash
# shiv cache — manages completion task caches

SHIV_CACHE_DIR="${SHIV_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/shiv}"

# Cache task list for a tool (name<TAB>description per line)
# Writes atomically — only replaces cache if new content is non-empty,
# so a failed mise invocation doesn't leave an empty cache file.
shiv_cache_tasks() {
  [ "${SHIV_SKIP_CACHE:-}" = "1" ] && return 0

  local name="$1" repo_dir="$2"
  local cache="$SHIV_CACHE_DIR/completions/$name.cache"
  local tmp="$cache.tmp"
  mkdir -p "$SHIV_CACHE_DIR/completions"
  mise tasks --json -C "$repo_dir" 2>/dev/null \
    | jq -r '.[] | select(.hide == false) | "\(.name)\t\(.description)"' \
    > "$tmp"
  if [ -s "$tmp" ]; then
    mv "$tmp" "$cache"
  else
    rm -f "$tmp"
  fi
}

# Remove cached tasks for a tool
shiv_cache_remove() {
  local name="$1"
  rm -f "$SHIV_CACHE_DIR/completions/$name.cache"
}
