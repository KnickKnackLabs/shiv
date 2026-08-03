#!/usr/bin/env bash
# shiv shim generation — the core mechanism
#
# This file creates and manages shims, and sources the other lib files
# for registry, cache, and source operations.

REPO_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$REPO_LIB_DIR/registry.sh"
source "$REPO_LIB_DIR/cache.sh"
source "$REPO_LIB_DIR/resolve.sh"
source "$REPO_LIB_DIR/sources.sh"

SHIV_BIN_DIR="${SHIV_BIN_DIR:-$HOME/.local/bin}"
SHIV_DATA_DIR="${SHIV_DATA_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/shiv}"
SHIV_PACKAGES_DIR="${SHIV_PACKAGES_DIR:-$SHIV_DATA_DIR/packages}"

# Create a shim for a tool
shiv_caller_pwd_var_name() {
  local name="$1"
  local var
  var=$(printf '%s' "$name" | tr '[:lower:]' '[:upper:]' | sed 's/[^A-Z0-9_]/_/g')
  case "$var" in
    [A-Z_]*) ;;
    *) var="_$var" ;;
  esac
  printf '%s_CALLER_PWD\n' "$var"
}

shiv_create_shim() {
  local name="$1" repo_dir="$2"
  local default_task=""
  local caller_pwd_var task_map_quoted
  caller_pwd_var=$(shiv_caller_pwd_var_name "$name")
  task_map_quoted=$(shiv_shell_quote "$SHIV_CACHE_DIR/tasks/$name")

  # At install time, detect a default task for single-command tools.
  # Checks .mise/tasks/<name> first, then .mise/tasks/_default.
  # Enables "numnum 3.14" instead of "numnum numnum 3.14".
  if [ -f "$repo_dir/.mise/tasks/$name" ]; then
    default_task="$name"
  elif [ -f "$repo_dir/.mise/tasks/_default" ]; then
    default_task="_default"
  fi

  # At install time, detect if the package has its own 'tasks' task.
  # If not, the shim intercepts `<name> tasks` to show the task list.
  local has_tasks_task=""
  if [ -f "$repo_dir/.mise/tasks/tasks" ]; then
    has_tasks_task="true"
  fi

  # At install time, detect if the package has its own 'help' task.
  # If present, the shim routes `--help`, `-h`, and `help` there.
  local has_help_task=""
  if [ -f "$repo_dir/.mise/tasks/help" ]; then
    has_help_task="true"
  fi

  mkdir -p "$SHIV_BIN_DIR"

  # Build the shim in three parts:
  # 1. Header + config (expanded heredoc — bakes in install-time values)
  # 2. Embedded resolver (quoted heredoc — no expansion, verbatim from lib/resolve.sh)
  # 3. Runtime logic (expanded heredoc — references both baked config and runtime vars)

  # Part 1: shebang, config, and helper functions
  cat > "$SHIV_BIN_DIR/$name" <<SCRIPT
#!/usr/bin/env bash
# managed by shiv
REPO="$repo_dir"
DEFAULT_TASK="${default_task}"
HAS_TASKS_TASK="${has_tasks_task}"
HAS_HELP_TASK="${has_help_task}"
SHIV_TASK_MAP=$task_map_quoted

_shiv_check_repo() {
  if [ ! -d "\$REPO" ]; then
    echo "$name: repo not found at \$REPO" >&2
    echo "$name: run 'shiv doctor' to diagnose" >&2
    exit 1
  fi
}

_shiv_check_cwd() {
  if [ "\$(basename "\$PWD")" = "$name" ] && [ "\$PWD" != "$repo_dir" ]; then
    echo "$name: warning: you're in a directory called '$name' but running the shiv-installed copy" >&2
    echo "$name: shiv package: $repo_dir" >&2
    echo "$name: current dir: \$PWD" >&2
    echo "$name: to run from this directory instead: mise run \$*" >&2
    echo "" >&2
  fi
}

_shiv_package_tasks_json() {
  unset MISE_OVERRIDE_CONFIG_FILENAMES
  mise tasks --json "\$@" -C "\$REPO" 2>/dev/null
}

_shiv_exec_package_mise() {
  unset MISE_OVERRIDE_CONFIG_FILENAMES
  exec mise -C "\$REPO" "\$@"
}

# NOTE: the task-map transformation duplicates shiv_cache_task_map() in
# lib/cache.sh (shim self-containment). If you change package-task cache
# invariants, update both places: scrub caller-scoped mise config overrides and
# exclude global mise tasks.
_shiv_ensure_task_map() {
  [ -f "\$SHIV_TASK_MAP" ] && return 0
  if ! command -v jq >/dev/null 2>&1; then
    echo "$name: warning: jq not found, space-to-colon resolution disabled" >&2
    return 0
  fi
  mkdir -p "\$(dirname "\$SHIV_TASK_MAP")"
  local tmp="\$SHIV_TASK_MAP.tmp"
  local tasks_json
  if ! tasks_json=\$(_shiv_package_tasks_json --hidden); then
    rm -f "\$tmp"
    return 0
  fi
  if [ -z "\$tasks_json" ]; then
    rm -f "\$tmp"
    return 0
  fi
  if ! printf '%s\n' "\$tasks_json" \\
    | jq -r '.[] | select(.global != true) | .name | gsub(":"; " ")' > "\$tmp" 2>/dev/null; then
    rm -f "\$tmp"
    return 0
  fi

  if [ -s "\$tmp" ]; then
    mv "\$tmp" "\$SHIV_TASK_MAP"
  else
    rm -f "\$tmp"
  fi
}

_shiv_render_tasks_plain() {
  awk -F '\t' '{ printf "%-12s  %-24s  %-16s  %s\n", \$1, \$2, \$3, \$4 }'
}

_shiv_render_tasks() {
  if ! command -v jq >/dev/null 2>&1; then
    echo "$name: jq not found, cannot render package-local task list" >&2
    return 1
  fi

  local tmp repo_prefix tasks_json
  tmp=\$(mktemp)
  repo_prefix="\$(cd "\$REPO" && pwd -P)/"
  if ! tasks_json=\$(_shiv_package_tasks_json --local); then
    rm -f "\$tmp"
    echo "$name: failed to render package-local task list" >&2
    return 1
  fi
  if ! printf '%s\n' "\$tasks_json" \
    | jq -r --arg repo_prefix "\$repo_prefix" '[.[] | select(.hide != true) | select(((.source // .file // "") | startswith(\$repo_prefix))) | (.name | split(":")) as \$p | {
        group: (if (\$p | length) > 1 then \$p[0] else "root" end),
        task: (if (\$p | length) > 1 then (\$p[1:] | join(":")) else .name end),
        aliases: ((.aliases // []) | join(", ")),
        description: (.description // "")
      }]
      | sort_by((if .group == "root" then "" else .group end), .task)
      | .[]
      | [.group, .task, .aliases, .description]
      | @tsv' > "\$tmp" 2>/dev/null; then
    rm -f "\$tmp"
    echo "$name: failed to render package-local task list" >&2
    return 1
  fi

  if [ ! -s "\$tmp" ]; then
    rm -f "\$tmp"
    echo "No local tasks found."
    return 0
  fi

  if command -v gum >/dev/null 2>&1 && [ -t 1 ]; then
    {
      printf 'Group\tTask\tAliases\tDescription\n'
      cat "\$tmp"
    } | gum table --print --separator \$'\t' --border rounded
  else
    {
      printf 'Group\tTask\tAliases\tDescription\n'
      cat "\$tmp"
    } | _shiv_render_tasks_plain
  fi

  rm -f "\$tmp"
}

_shiv_handle_tasks() {
  if [ "\$HAS_TASKS_TASK" = "true" ]; then
    _shiv_exec_package_mise run -q "\$@"
  fi
  _shiv_render_tasks
  local rc=\$?
  echo "" >&2
  echo "To override this output, create .mise/tasks/tasks in the package and reinstall." >&2
  exit \$rc
}

_shiv_handle_help() {
  local help_arg="\${1:-help}"

  # Package-owned help wins. This lets tools expose richer help than the
  # generic mise task list while keeping the shim-level interception.
  if [ "\$HAS_HELP_TASK" = "true" ]; then
    _shiv_exec_package_mise run -q help
  fi

  # Single-command tools (.mise/tasks/<name>) should show the command help,
  # not the package task list. Do not do this for _default: those are often
  # menus/catch-alls where task-list help is still the safer default.
  if [ -n "\$DEFAULT_TASK" ] && [ "\$DEFAULT_TASK" != "_default" ]; then
    if [ "\$help_arg" = "help" ]; then
      _shiv_exec_package_mise run -q "\$DEFAULT_TASK" help
    else
      _shiv_exec_package_mise run -q "\$DEFAULT_TASK" "\$help_arg"
    fi
  fi

  _shiv_handle_tasks tasks
}

_shiv_handle_version() {
  local version branch updated git_prefix git_var

  # Git exports repository-selection variables to hooks. Clear them before
  # inspecting the package so caller metadata cannot override git -C.
  while IFS= read -r git_var; do
    [ -n "\$git_var" ] && unset "\$git_var"
  done < <(git rev-parse --local-env-vars 2>/dev/null)

  # git -C searches parent directories. Require the package itself to be the
  # worktree root so a non-Git local package cannot inherit unrelated metadata.
  if ! git_prefix=\$(git -C "\$REPO" rev-parse --show-prefix 2>/dev/null) || [ -n "\$git_prefix" ]; then
    version="unknown"
  elif ! version=\$(git -C "\$REPO" describe --tags --exact-match HEAD 2>/dev/null); then
    version=\$(git -C "\$REPO" rev-parse --short HEAD 2>/dev/null || printf 'unknown')
  fi

  if [ "\$version" = "unknown" ]; then
    branch="unknown"
    updated="unknown"
  else
    if [ -n "\$(git -C "\$REPO" status --porcelain 2>/dev/null)" ]; then
      version="\${version}*"
    fi
    branch=\$(git -C "\$REPO" symbolic-ref --quiet --short HEAD 2>/dev/null || printf 'detached')
    updated=\$(git -C "\$REPO" log -1 --format='%cd' --date=relative 2>/dev/null || printf 'unknown')
  fi

  printf '%s %s (branch: %s, updated: %s)\n' "$name" "\$version" "\$branch" "\$updated"
}

SCRIPT

  {
    # Part 2: embed resolver function (quoted heredoc — no variable expansion)
    cat <<'RESOLVE'
# --- embedded from lib/resolve.sh ---
RESOLVE
    # Strip the shebang line and inject the function body
    sed '1{/^#!/d;}' "$REPO_LIB_DIR/resolve.sh"
    echo '# --- end embedded resolver ---'
    echo ''

    # Part 3: main dispatch logic
    cat <<SCRIPT

# --- main ---
_shiv_check_repo
export ${caller_pwd_var}="\$PWD"
_shiv_check_cwd "\$@"

case "\${1:-}" in
  --help|-h|help)
    _shiv_handle_help "\${1:-help}"
    ;;
  --version)
    _shiv_handle_version
    ;;
  tasks)
    _shiv_handle_tasks "\$@"
    ;;
  *)
    # --- Default task handling ---
    # No args: run default task directly.
    if [ -n "\$DEFAULT_TASK" ] && [ -z "\${1:-}" ]; then
      _shiv_exec_package_mise run -q "\$DEFAULT_TASK"
    fi

    # "--" as first arg: explicit disambiguation — send everything
    # after "--" to the default task.
    if [ -n "\$DEFAULT_TASK" ] && [ "\${1:-}" = "--" ]; then
      shift
      if [ \$# -gt 0 ]; then
        _shiv_exec_package_mise run -q "\$DEFAULT_TASK" "\$@"
      else
        _shiv_exec_package_mise run -q "\$DEFAULT_TASK"
      fi
    fi

    # Check if "--" is present in args (user is disambiguating).
    _shiv_has_dash=false
    for _shiv_arg in "\$@"; do
      if [ "\$_shiv_arg" = "--" ]; then
        _shiv_has_dash=true
        break
      fi
    done

    # Space-to-colon resolution
    _shiv_ensure_task_map
    shiv_resolve_task "$name" "\$SHIV_TASK_MAP" "\$@"
    _shiv_rc=\$?
    if [ "\$_shiv_rc" -eq 0 ]; then
      # Resolved a subtask. If a default task also exists and the user
      # didn't use "--" to disambiguate, this is ambiguous.
      if [ -n "\$DEFAULT_TASK" ] && [ "\$_shiv_has_dash" = "false" ]; then
        echo "Ambiguous: '\$*' could be:" >&2
        echo "  task '\$SHIV_RESOLVED_TASK' with args: \${SHIV_RESOLVED_ARGS[*]:-<none>}" >&2
        echo "  default task with args: \$*" >&2
        echo "Use -- to disambiguate:" >&2
        echo "  $name \${SHIV_RESOLVED_TASK//:/ } -- \${SHIV_RESOLVED_ARGS[*]}     (task '\$SHIV_RESOLVED_TASK')" >&2
        echo "  $name -- \$*     (default task)" >&2
        exit 1
      fi
      # Guard: only expand SHIV_RESOLVED_ARGS when non-empty.
      # bash <4.4 treats "\${empty_array[@]}" as unbound under set -u.
      if [ \${#SHIV_RESOLVED_ARGS[@]} -gt 0 ]; then
        _shiv_exec_package_mise run -q "\$SHIV_RESOLVED_TASK" "\${SHIV_RESOLVED_ARGS[@]}"
      else
        _shiv_exec_package_mise run -q "\$SHIV_RESOLVED_TASK"
      fi
    elif [ "\$_shiv_rc" -eq 1 ]; then
      exit 1  # ambiguous — error already printed to stderr
    fi
    # rc=2 or no task map: fall through to default task or mise
    if [ -n "\$DEFAULT_TASK" ]; then
      _shiv_exec_package_mise run -q "\$DEFAULT_TASK" "\$@"
    fi
    _shiv_exec_package_mise run -q "\$@"
    ;;
esac
SCRIPT
  } >> "$SHIV_BIN_DIR/$name"

  chmod +x "$SHIV_BIN_DIR/$name"
}

# Create alias symlinks for a package (relative, same directory)
shiv_create_alias_symlinks() {
  local name="$1"
  shift
  local aliases=("$@")
  for alias in "${aliases[@]}"; do
    ln -sf "$name" "$SHIV_BIN_DIR/$alias"
  done
}

# Quote a value for POSIX-ish shell eval output.
shiv_shell_quote() {
  printf "'"
  printf '%s' "$1" | sed "s/'/'\\\\''/g"
  printf "'"
}

# Remove exact PATH entries from a colon-separated path string.
shiv_path_remove_entries() {
  local path_value="$1"
  shift

  local result=""
  local result_set="false"
  local entry=""
  local remove=""
  local remainder="$path_value:"
  local skip="false"

  while [ -n "$remainder" ]; do
    entry="${remainder%%:*}"
    remainder="${remainder#*:}"

    skip="false"
    for remove in "$@"; do
      if [ "$entry" = "$remove" ]; then
        skip="true"
        break
      fi
    done

    if [ "$skip" = "false" ]; then
      if [ "$result_set" = "true" ]; then
        result="$result:$entry"
      else
        result="$entry"
        result_set="true"
      fi
    fi
  done

  printf '%s\n' "$result"
}

# Emit shell export statements to put shiv's bin dir and mise's shims dir on PATH.
# Designed to be eval'd: `eval "$(shiv_emit_path_exports)"`
# Mise shims must precede SHIV_BIN_DIR so repo-scoped mise pins win over the
# global shiv shim. Normalize order and de-duplicate, instead of only checking
# that both directories are present somewhere on PATH.
shiv_emit_path_exports() {
  local current_path="${PATH:-}"
  local mise_shims_dir="${MISE_DATA_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/mise}/shims"
  local path_rest=""
  local normalized_path=""

  if [ -d "$mise_shims_dir" ]; then
    path_rest=$(shiv_path_remove_entries "$current_path" "$mise_shims_dir" "$SHIV_BIN_DIR")
    normalized_path="$mise_shims_dir:$SHIV_BIN_DIR"
  else
    path_rest=$(shiv_path_remove_entries "$current_path" "$SHIV_BIN_DIR")
    normalized_path="$SHIV_BIN_DIR"
  fi

  if [ -n "$path_rest" ]; then
    normalized_path="$normalized_path:$path_rest"
  fi

  [ "$normalized_path" = "$current_path" ] && return 0

  printf 'export PATH=%s\n' "$(shiv_shell_quote "$normalized_path")"
}

# Remove alias symlinks for a package (only if they point to the expected target)
shiv_remove_alias_symlinks() {
  local name="$1"
  shift
  local aliases=("$@")
  for alias in "${aliases[@]}"; do
    if [ -L "$SHIV_BIN_DIR/$alias" ] && [ "$(readlink "$SHIV_BIN_DIR/$alias")" = "$name" ]; then
      rm -f "$SHIV_BIN_DIR/$alias"
    fi
  done
}
