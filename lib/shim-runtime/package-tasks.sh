#!/usr/bin/env bash
# Embedded in installed shims; configuration is supplied by lib/shim.sh.

_shiv_check_repo() {
  if [ ! -d "$REPO" ]; then
    echo "$SHIV_PACKAGE_NAME: repo not found at $REPO" >&2
    echo "$SHIV_PACKAGE_NAME: run 'shiv doctor' to diagnose" >&2
    exit 1
  fi
}

_shiv_check_cwd() {
  if [ "$(basename "$PWD")" = "$SHIV_PACKAGE_NAME" ] && [ "$PWD" != "$REPO" ]; then
    echo "$SHIV_PACKAGE_NAME: warning: you're in a directory called '$SHIV_PACKAGE_NAME' but running the shiv-installed copy" >&2
    echo "$SHIV_PACKAGE_NAME: shiv package: $REPO" >&2
    echo "$SHIV_PACKAGE_NAME: current dir: $PWD" >&2
    echo "$SHIV_PACKAGE_NAME: to run from this directory instead: mise run $*" >&2
    echo "" >&2
  fi
}

_shiv_package_tasks_json() {
  unset MISE_OVERRIDE_CONFIG_FILENAMES
  mise tasks --json "$@" -C "$REPO" 2>/dev/null
}

_shiv_exec_package_mise() {
  unset MISE_OVERRIDE_CONFIG_FILENAMES
  exec mise -C "$REPO" "$@"
}

# NOTE: the task-map transformation duplicates shiv_cache_task_map() in
# lib/cache.sh (shim self-containment). If you change package-task cache
# invariants, update both places: scrub caller-scoped mise config overrides and
# exclude global mise tasks.
_shiv_ensure_task_map() {
  [ -f "$SHIV_TASK_MAP" ] && return 0
  if ! command -v jq >/dev/null 2>&1; then
    echo "$SHIV_PACKAGE_NAME: warning: jq not found, space-to-colon resolution disabled" >&2
    return 0
  fi
  mkdir -p "$(dirname "$SHIV_TASK_MAP")"
  local tmp="$SHIV_TASK_MAP.tmp"
  local tasks_json
  if ! tasks_json=$(_shiv_package_tasks_json --hidden); then
    rm -f "$tmp"
    return 0
  fi
  if [ -z "$tasks_json" ]; then
    rm -f "$tmp"
    return 0
  fi
  if ! printf '%s\n' "$tasks_json" \
    | jq -r '.[] | select(.global != true) | .name | gsub(":"; " ")' > "$tmp" 2>/dev/null; then
    rm -f "$tmp"
    return 0
  fi

  if [ -s "$tmp" ]; then
    mv "$tmp" "$SHIV_TASK_MAP"
  else
    rm -f "$tmp"
  fi
}

_shiv_render_tasks_plain() {
  awk -F '\t' '{ printf "%-12s  %-24s  %-16s  %s\n", $1, $2, $3, $4 }'
}

_shiv_render_tasks() {
  if ! command -v jq >/dev/null 2>&1; then
    echo "$SHIV_PACKAGE_NAME: jq not found, cannot render package-local task list" >&2
    return 1
  fi

  local tmp repo_prefix tasks_json
  tmp=$(mktemp)
  repo_prefix="$(cd "$REPO" && pwd -P)/"
  if ! tasks_json=$(_shiv_package_tasks_json --local); then
    rm -f "$tmp"
    echo "$SHIV_PACKAGE_NAME: failed to render package-local task list" >&2
    return 1
  fi
  if ! printf '%s\n' "$tasks_json" \
    | jq -r --arg repo_prefix "$repo_prefix" '[.[] | select(.hide != true) | select(((.source // .file // "") | startswith($repo_prefix))) | (.name | split(":")) as $p | {
        group: (if ($p | length) > 1 then $p[0] else "root" end),
        task: (if ($p | length) > 1 then ($p[1:] | join(":")) else .name end),
        aliases: ((.aliases // []) | join(", ")),
        description: (.description // "")
      }]
      | sort_by((if .group == "root" then "" else .group end), .task)
      | .[]
      | [.group, .task, .aliases, .description]
      | @tsv' > "$tmp" 2>/dev/null; then
    rm -f "$tmp"
    echo "$SHIV_PACKAGE_NAME: failed to render package-local task list" >&2
    return 1
  fi

  if [ ! -s "$tmp" ]; then
    rm -f "$tmp"
    echo "No local tasks found."
    return 0
  fi

  if command -v gum >/dev/null 2>&1 && [ -t 1 ]; then
    {
      printf 'Group\tTask\tAliases\tDescription\n'
      cat "$tmp"
    } | gum table --print --separator $'\t' --border rounded
  else
    {
      printf 'Group\tTask\tAliases\tDescription\n'
      cat "$tmp"
    } | _shiv_render_tasks_plain
  fi

  rm -f "$tmp"
}

_shiv_handle_tasks() {
  if [ "$HAS_TASKS_TASK" = "true" ]; then
    _shiv_exec_package_mise run -q "$@"
  fi
  _shiv_render_tasks
  local rc=$?
  echo "" >&2
  echo "To override this output, create .mise/tasks/tasks in the package and reinstall." >&2
  exit $rc
}

_shiv_handle_help() {
  local help_arg="${1:-help}"

  # Package-owned help wins. This lets tools expose richer help than the
  # generic mise task list while keeping the shim-level interception.
  if [ "$HAS_HELP_TASK" = "true" ]; then
    _shiv_exec_package_mise run -q help
  fi

  # Single-command tools (.mise/tasks/<name>) should show the command help,
  # not the package task list. Do not do this for _default: those are often
  # menus/catch-alls where task-list help is still the safer default.
  if [ -n "$DEFAULT_TASK" ] && [ "$DEFAULT_TASK" != "_default" ]; then
    if [ "$help_arg" = "help" ]; then
      _shiv_exec_package_mise run -q "$DEFAULT_TASK" help
    else
      _shiv_exec_package_mise run -q "$DEFAULT_TASK" "$help_arg"
    fi
  fi

  _shiv_handle_tasks tasks
}
