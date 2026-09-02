#!/usr/bin/env bash
# shiv cache — manages completion and task map caches

SHIV_CACHE_DIR="${SHIV_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/shiv}"

# Return package-local task metadata from mise without inheriting caller-scoped
# config overrides. Shiv caches describe the managed package, not the repo or CI
# wrapper that happened to invoke shiv.
shiv_package_tasks_json() {
  local repo_dir="$1"
  shift

  (
    unset MISE_OVERRIDE_CONFIG_FILENAMES
    mise tasks --json "$@" -C "$repo_dir" 2>/dev/null
  )
}

# Report whether mise can read the package's config well enough to list tasks.
# Ignores SHIV_SKIP_CACHE — this is a validity check, not a cache refresh.
shiv_package_tasks_discoverable() {
  local repo_dir="$1"
  local err

  if err=$(
    unset MISE_OVERRIDE_CONFIG_FILENAMES
    mise tasks --json -C "$repo_dir" 2>&1 >/dev/null
  ); then
    return 0
  fi

  printf '%s\n' "$err"
  return 1
}

# Cache task list for a tool (name<TAB>description per line).
# Writes atomically and preserves the old cache if task discovery fails.
# Pass "true" as the third argument when discovery failure must be reported.
shiv_cache_tasks() {
  [ "${SHIV_SKIP_CACHE:-}" = "1" ] && return 0

  local name="$1" repo_dir="$2" require_refresh="${3:-false}"
  local cache="$SHIV_CACHE_DIR/completions/$name.cache"
  local tmp="$cache.tmp"
  mkdir -p "$SHIV_CACHE_DIR/completions"
  local tasks_json
  if ! tasks_json=$(shiv_package_tasks_json "$repo_dir"); then
    rm -f "$tmp"
    if [ "$require_refresh" = "true" ]; then
      return 1
    fi
    return 0
  fi
  if [ -z "$tasks_json" ]; then
    rm -f "$tmp" "$cache"
    return 0
  fi
  if ! printf '%s\n' "$tasks_json" \
    | jq -r '.[] | select(.global != true) | select(.hide == false) | "\(.name)\t\(.description)"' \
    > "$tmp"; then
    rm -f "$tmp"
    if [ "$require_refresh" = "true" ]; then
      return 1
    fi
    return 0
  fi
  if [ -s "$tmp" ]; then
    mv "$tmp" "$cache"
  else
    rm -f "$tmp" "$cache"
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

  local name="$1" repo_dir="$2" require_refresh="${3:-false}"
  local cache="$SHIV_CACHE_DIR/tasks/$name"
  local tmp="$cache.tmp"
  mkdir -p "$SHIV_CACHE_DIR/tasks"
  local tasks_json
  if ! tasks_json=$(shiv_package_tasks_json "$repo_dir" --hidden); then
    rm -f "$tmp"
    if [ "$require_refresh" = "true" ]; then
      return 1
    fi
    return 0
  fi
  if [ -z "$tasks_json" ]; then
    rm -f "$tmp" "$cache"
    return 0
  fi
  if ! printf '%s\n' "$tasks_json" \
    | jq -r '.[] | select(.global != true) | .name | gsub(":"; " ")' \
    > "$tmp"; then
    rm -f "$tmp"
    if [ "$require_refresh" = "true" ]; then
      return 1
    fi
    return 0
  fi

  if [ -s "$tmp" ]; then
    mv "$tmp" "$cache"
  else
    rm -f "$tmp" "$cache"
  fi
}

# Remove all cached data for a tool
shiv_cache_remove() {
  local name="$1"
  rm -f "$SHIV_CACHE_DIR/completions/$name.cache"
  rm -f "$SHIV_CACHE_DIR/tasks/$name"
}
