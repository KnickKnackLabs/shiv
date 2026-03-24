#!/usr/bin/env bash
# shiv shim generation — the core mechanism
#
# This file creates and manages shims, and sources the other lib files
# for registry, cache, and source operations.

REPO_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$REPO_LIB_DIR/registry.sh"
source "$REPO_LIB_DIR/cache.sh"
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
  cat > "$SHIV_BIN_DIR/$name" <<SCRIPT
#!/usr/bin/env bash
# managed by shiv
REPO="$repo_dir"
DEFAULT_TASK="${default_task}"
HAS_TASKS_TASK="${has_tasks_task}"
if [ ! -d "\$REPO" ]; then
  echo "$name: repo not found at \$REPO" >&2
  echo "$name: run 'shiv doctor' to diagnose" >&2
  exit 1
fi
export CALLER_PWD="\$PWD"
if [ "\$(basename "\$PWD")" = "$name" ] && [ "\$PWD" != "$repo_dir" ]; then
  echo "$name: warning: you're in a directory called '$name' but running the shiv-installed copy" >&2
  echo "$name: shiv package: $repo_dir" >&2
  echo "$name: current dir: \$PWD" >&2
  echo "$name: to run from this directory instead: mise run \$*" >&2
  echo "" >&2
fi
case "\${1:-}" in
  --help|-h|help)
    exec mise -C "\$REPO" tasks
    ;;
  tasks)
    if [ "\$HAS_TASKS_TASK" = "true" ]; then
      exec mise -C "\$REPO" run -q "\$@"
    fi
    mise -C "\$REPO" tasks
    echo "" >&2
    echo "To override this output, create .mise/tasks/tasks in the package." >&2
    exit 0
    ;;
  *)
    if [ -n "\$DEFAULT_TASK" ] && [ -z "\${1:-}" ]; then
      exec mise -C "\$REPO" run -q "\$DEFAULT_TASK"
    elif [ -n "\$DEFAULT_TASK" ]; then
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
