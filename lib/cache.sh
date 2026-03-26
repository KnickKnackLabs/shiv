#!/usr/bin/env bash
# shiv cache — manages completion and task map caches

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

# Cache task map for a tool (space-separated task paths, one per line)
# Used by the shim to resolve space-separated arguments into colon-joined
# mise task names. Colons in task names become spaces:
#   agent:message  →  agent message
#   dev:test:unit  →  dev test unit
# Idempotent — safe to call from install, update, or shim (cache miss).
#
# NOTE: the mise tasks | jq pipeline is duplicated in _shiv_ensure_task_map()
# in lib/shim.sh (shim self-containment). If you change the format, update both.
shiv_cache_task_map() {
  [ "${SHIV_SKIP_CACHE:-}" = "1" ] && return 0

  local name="$1" repo_dir="$2"
  local cache="$SHIV_CACHE_DIR/tasks/$name"
  local tmp="$cache.tmp"
  mkdir -p "$SHIV_CACHE_DIR/tasks"
  mise tasks --json --hidden -C "$repo_dir" 2>/dev/null \
    | jq -r '.[].name | gsub(":"; " ")' \
    > "$tmp" || true
  if [ -s "$tmp" ]; then
    mv "$tmp" "$cache"
  else
    rm -f "$tmp"
  fi
}

# Remove all cached data for a tool
shiv_cache_remove() {
  local name="$1"
  rm -f "$SHIV_CACHE_DIR/completions/$name.cache"
  rm -f "$SHIV_CACHE_DIR/tasks/$name"
}
