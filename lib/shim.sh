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
shiv_create_shim() {
  local name="$1" repo_dir="$2"
  local default_task=""

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
SHIV_TASK_MAP="\${XDG_CACHE_HOME:-\$HOME/.cache}/shiv/tasks/$name"

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

# NOTE: the mise tasks | jq pipeline below duplicates shiv_cache_task_map()
# in lib/cache.sh (shim self-containment). If you change the format, update both.
_shiv_ensure_task_map() {
  [ -f "\$SHIV_TASK_MAP" ] && return 0
  if ! command -v jq >/dev/null 2>&1; then
    echo "$name: warning: jq not found, space-to-colon resolution disabled" >&2
    return 0
  fi
  mkdir -p "\$(dirname "\$SHIV_TASK_MAP")"
  local tmp="\$SHIV_TASK_MAP.tmp"
  mise tasks --json --hidden -C "\$REPO" 2>/dev/null \\
    | jq -r '.[].name | gsub(":"; " ")' > "\$tmp" 2>/dev/null || true
  if [ -s "\$tmp" ]; then
    mv "\$tmp" "\$SHIV_TASK_MAP"
  else
    rm -f "\$tmp"
  fi
}

_shiv_handle_tasks() {
  if [ "\$HAS_TASKS_TASK" = "true" ]; then
    exec mise -C "\$REPO" run -q "\$@"
  fi
  mise -C "\$REPO" tasks
  local rc=\$?
  echo "" >&2
  echo "To override this output, create .mise/tasks/tasks in the package and reinstall." >&2
  exit \$rc
}

SCRIPT

  # Part 2: embed resolver function (quoted heredoc — no variable expansion)
  cat >> "$SHIV_BIN_DIR/$name" <<'RESOLVE'
# --- embedded from lib/resolve.sh ---
RESOLVE
  # Strip the shebang line and inject the function body
  sed '1{/^#!/d;}' "$REPO_LIB_DIR/resolve.sh" >> "$SHIV_BIN_DIR/$name"
  echo '# --- end embedded resolver ---' >> "$SHIV_BIN_DIR/$name"
  echo '' >> "$SHIV_BIN_DIR/$name"

  # Part 3: main dispatch logic
  cat >> "$SHIV_BIN_DIR/$name" <<SCRIPT

# --- main ---
_shiv_check_repo
export CALLER_PWD="\$PWD"
_shiv_check_cwd "\$@"

case "\${1:-}" in
  --help|-h|help)
    exec mise -C "\$REPO" tasks
    ;;
  tasks)
    _shiv_handle_tasks "\$@"
    ;;
  *)
    # --- Default task handling ---
    # No args: run default task directly.
    if [ -n "\$DEFAULT_TASK" ] && [ -z "\${1:-}" ]; then
      exec mise -C "\$REPO" run -q "\$DEFAULT_TASK"
    fi

    # "--" as first arg: explicit disambiguation — send everything
    # after "--" to the default task.
    if [ -n "\$DEFAULT_TASK" ] && [ "\${1:-}" = "--" ]; then
      shift
      if [ \$# -gt 0 ]; then
        exec mise -C "\$REPO" run -q "\$DEFAULT_TASK" "\$@"
      else
        exec mise -C "\$REPO" run -q "\$DEFAULT_TASK"
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
        exec mise -C "\$REPO" run -q "\$SHIV_RESOLVED_TASK" "\${SHIV_RESOLVED_ARGS[@]}"
      else
        exec mise -C "\$REPO" run -q "\$SHIV_RESOLVED_TASK"
      fi
    elif [ "\$_shiv_rc" -eq 1 ]; then
      exit 1  # ambiguous — error already printed to stderr
    fi
    # rc=2 or no task map: fall through to default task or mise
    if [ -n "\$DEFAULT_TASK" ]; then
      exec mise -C "\$REPO" run -q "\$DEFAULT_TASK" "\$@"
    fi
    exec mise -C "\$REPO" run -q "\$@"
    ;;
esac
SCRIPT

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

# Emit shell export statements to put shiv's bin dir and mise's shims dir on PATH.
# Designed to be eval'd: `eval "$(shiv_emit_path_exports)"`
# Mise shims are emitted after SHIV_BIN_DIR so they end up first on PATH —
# when a directory's mise.toml pins a version, the mise shim wins over the
# global shiv shim.
shiv_emit_path_exports() {
  # Ensure SHIV_BIN_DIR (~/.local/bin) is on PATH
  case ":$PATH:" in
    *":$SHIV_BIN_DIR:"*) ;;
    *) echo "export PATH=\"$SHIV_BIN_DIR:\$PATH\"" ;;
  esac

  # Ensure mise shims are on PATH so shiv packages installed via vfox-shiv
  # resolve correctly in non-interactive shells (agent sessions, scripts, etc.).
  local mise_shims_dir="${MISE_DATA_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/mise}/shims"
  if [ -d "$mise_shims_dir" ]; then
    case ":$PATH:" in
      *":$mise_shims_dir:"*) ;;
      *) echo "export PATH=\"$mise_shims_dir:\$PATH\"" ;;
    esac
  fi
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
