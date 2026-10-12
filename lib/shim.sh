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
source "$REPO_LIB_DIR/caller-env.sh"

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
  local caller_pwd_var caller_owner package_dir directory_key task_map_quoted
  caller_pwd_var=$(shiv_caller_pwd_var_name "$name")
  caller_owner=$(shiv_caller_env_key "$name") || return 1
  package_dir=$(cd "$repo_dir" && pwd -P) || return 1
  directory_key=$(shiv_caller_env_key "$package_dir") || return 1
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

  mkdir -p "$SHIV_BIN_DIR" || return 1
  local shim_tmp
  shim_tmp=$(mktemp "$SHIV_BIN_DIR/.${name}.XXXXXX") || return 1

  # Assemble beside the destination so a failed read cannot replace a working shim.
  # The installed shim never reads these source files at runtime.
  if ! {
    printf '%s\n' '#!/usr/bin/env bash' '# managed by shiv' &&
    printf 'SHIV_PACKAGE_NAME=%s\n' "$(shiv_shell_quote "$name")" &&
    printf 'REPO=%s\n' "$(shiv_shell_quote "$repo_dir")" &&
    printf 'DEFAULT_TASK=%s\n' "$(shiv_shell_quote "$default_task")" &&
    printf 'HAS_TASKS_TASK=%s\n' "$(shiv_shell_quote "$has_tasks_task")" &&
    printf 'HAS_HELP_TASK=%s\n' "$(shiv_shell_quote "$has_help_task")" &&
    printf 'SHIV_TASK_MAP=%s\n' "$task_map_quoted" &&
    printf 'SHIV_CALLER_OWNER=%s\n' "$(shiv_shell_quote "$caller_owner")" &&
    printf 'SHIV_DIRECTORY_KEY=%s\n' "$(shiv_shell_quote "$directory_key")" &&
    printf 'SHIV_CALLER_PWD_VAR=%s\n' "$(shiv_shell_quote "$caller_pwd_var")" &&
    printf 'SHIV_SETTING_PREFIX=%s\n' "$(shiv_shell_quote "${caller_pwd_var%CALLER_PWD}")" &&
    printf '\n' &&

    shiv_embed_shim_source "$REPO_LIB_DIR/shim-runtime/package-tasks.sh" &&
    shiv_embed_shim_source "$REPO_LIB_DIR/resolve.sh" &&
    shiv_embed_shim_source "$REPO_LIB_DIR/caller-env.sh" &&
    shiv_embed_shim_source "$REPO_LIB_DIR/shim-runtime/dispatch.sh"
  } > "$shim_tmp"; then
    rm -f "$shim_tmp"
    return 1
  fi

  if ! chmod 755 "$shim_tmp" || ! mv -f "$shim_tmp" "$SHIV_BIN_DIR/$name"; then
    rm -f "$shim_tmp"
    return 1
  fi
}

# Source fragments are install-time inputs, not runtime dependencies.
shiv_embed_shim_source() {
  local source_file="$1"
  printf '# --- embedded: %s ---\n' "${source_file#"$REPO_LIB_DIR/"}" || return 1
  sed '1{/^#!/d;}' "$source_file" || return 1
  printf '\n'
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
