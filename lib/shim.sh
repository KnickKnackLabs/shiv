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
source "$REPO_LIB_DIR/shim-restoration.sh"

SHIV_BIN_DIR="${SHIV_BIN_DIR:-$HOME/.local/bin}"
SHIV_DATA_DIR="${SHIV_DATA_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/shiv}"
SHIV_PACKAGES_DIR="${SHIV_PACKAGES_DIR:-$SHIV_DATA_DIR/packages}"

shiv_canonical_package_path() {
  local package_root="$1"

  if [ -d "$package_root" ]; then
    (cd "$package_root" && pwd -P)
  else
    printf '%s\n' "$package_root"
  fi
}

shiv_mise_scoped_package_path() {
  local name="$1"
  local caller_dir="$2"
  local mise_bin="${MISE_BIN:-mise}"
  local executable package_root

  if ! executable=$("$mise_bin" -C "$caller_dir" which "$name" 2>/dev/null); then
    return 1
  fi

  [ -f "$executable" ] || return 1
  grep -q "# managed by shiv" "$executable" 2>/dev/null || return 1

  package_root=$(shiv_read_generated_repo "$executable") || return 1
  printf '%s\n' "$package_root"
}

shiv_global_package_path() {
  local name="$1"
  local package_root resolved

  package_root=$(shiv_registry_path "$name")
  if [ -z "$package_root" ]; then
    resolved=$(shiv_registry_resolve "$name")
    if [ -n "$resolved" ]; then
      package_root=$(shiv_registry_path "$resolved")
    fi
  fi

  [ -n "$package_root" ] || return 1
  printf '%s\n' "$package_root"
}

shiv_active_mise_package_names() {
  local caller_dir="$1"
  local mise_bin="${MISE_BIN:-mise}"
  local tools_json active_names

  if ! tools_json=$("$mise_bin" -C "$caller_dir" ls --json 2>/dev/null); then
    echo "shiv: failed to inspect active mise tools from $caller_dir" >&2
    return 1
  fi

  if ! active_names=$(printf '%s\n' "$tools_json" | jq -r '
    to_entries[]
    | select(.key | startswith("shiv:"))
    | select(any(.value[]?; .active == true))
    | .key | sub("^shiv:"; "")
  '); then
    echo "shiv: mise returned invalid tool inventory for $caller_dir" >&2
    return 1
  fi

  printf '%s\n' "$active_names"
}

shiv_assert_active_package_matches_registry() {
  local name="$1"
  local registry_root="$2"
  local caller_dir="$3"
  local require_active="${4:-false}"
  local active_root active_canonical registry_canonical

  if ! active_root=$(shiv_mise_scoped_package_path "$name" "$caller_dir"); then
    if [ "$require_active" = "true" ]; then
      echo "shiv: failed to resolve active mise package 'shiv:$name' from $caller_dir" >&2
      return 1
    fi
    return 0
  fi

  active_canonical=$(shiv_canonical_package_path "$active_root")
  registry_canonical=$(shiv_canonical_package_path "$registry_root")
  [ "$active_canonical" = "$registry_canonical" ] && return 0

  cat >&2 <<EOF
shiv: active mise package root differs from the global registry for '$name'
  active mise root:    $active_canonical
  global registry root: $registry_canonical
  caller:              $caller_dir
Refusing to inspect or modify the registry package while this codebase executes a different checkout.
Use mise to refresh the active 'shiv:$name' tool, or run from a directory where it is not active.
EOF
  return 1
}

shiv_assert_active_packages_match_registry() {
  local caller_dir="$1"
  local active_names name registry_root

  active_names=$(shiv_active_mise_package_names "$caller_dir") || return 1
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    if registry_root=$(shiv_global_package_path "$name"); then
      shiv_assert_active_package_matches_registry "$name" "$registry_root" "$caller_dir" true || return 1
    fi
  done <<< "$active_names"
}

shiv_assert_active_registry_package_matches() {
  local registry_name="$1"
  local registry_root="$2"
  local caller_dir="$3"
  local active_names active_name resolved

  active_names=$(shiv_active_mise_package_names "$caller_dir") || return 1
  while IFS= read -r active_name; do
    [ -n "$active_name" ] || continue
    resolved=$(shiv_registry_resolve "$active_name")
    [ "$resolved" = "$registry_name" ] || continue
    shiv_assert_active_package_matches_registry "$active_name" "$registry_root" "$caller_dir" true || return 1
  done <<< "$active_names"
}

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
  local caller_pwd_var caller_owner package_dir directory_key task_map_quoted repo_escaped
  caller_pwd_var=$(shiv_caller_pwd_var_name "$name")
  caller_owner=$(shiv_caller_env_key "$name") || return 1
  package_dir=$(cd "$repo_dir" && pwd -P) || return 1
  directory_key=$(shiv_caller_env_key "$package_dir") || return 1
  repo_escaped=$(shiv_double_quote_escape "$repo_dir") || return 1
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
  # Mise separates trusted paths with colons. Refuse an ambiguous cache path
  # instead of accidentally trusting a shorter, unrelated prefix.
  case "$SHIV_CACHE_DIR" in
    *:*) printf '%s\n' 'shiv: shim cache path cannot contain a colon' >&2; return 1 ;;
  esac

  local shim_tmp restoration_root restoration_dir
  shim_tmp=$(mktemp "$SHIV_BIN_DIR/.${name}.XXXXXX") || return 1

  # These artifacts contain only source and paths. Private directories prevent
  # another OS user from replacing code that the shim asks Mise to trust.
  if ! (umask 077; mkdir -p "$SHIV_CACHE_DIR/shim-env"); then
    rm -f "$shim_tmp"
    return 1
  fi
  restoration_root=$(cd "$SHIV_CACHE_DIR/shim-env" && pwd -P) || {
    rm -f "$shim_tmp"
    return 1
  }
  case "$restoration_root" in
    *:*)
      printf '%s\n' 'shiv: shim cache path cannot contain a colon' >&2
      rm -f "$shim_tmp"
      return 1
      ;;
  esac
  restoration_dir=$(mktemp -d "$restoration_root/${caller_owner}.XXXXXX") || {
    rm -f "$shim_tmp"
    return 1
  }
  if ! shiv_create_restoration "$package_dir" "$restoration_dir" "$caller_owner"; then
    rm -f "$shim_tmp"
    rm -rf "$restoration_dir"
    return 1
  fi

  # Assemble beside the destination so a failed read cannot replace a working shim.
  # The installed shim never reads these source files at runtime.
  if ! {
    printf '%s\n' '#!/usr/bin/env bash' '# managed by shiv' &&
    printf 'SHIV_PACKAGE_NAME=%s\n' "$(shiv_shell_quote "$name")" &&
    printf 'REPO="%s"\n' "$repo_escaped" &&
    printf 'DEFAULT_TASK=%s\n' "$(shiv_shell_quote "$default_task")" &&
    printf 'HAS_TASKS_TASK=%s\n' "$(shiv_shell_quote "$has_tasks_task")" &&
    printf 'HAS_HELP_TASK=%s\n' "$(shiv_shell_quote "$has_help_task")" &&
    printf 'SHIV_TASK_MAP=%s\n' "$task_map_quoted" &&
    printf 'SHIV_RESTORATION_CONFIG=%s\n' "$(shiv_shell_quote "$restoration_dir/restore.toml")" &&
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
    rm -rf "$restoration_dir"
    return 1
  fi

  if ! chmod 400 "$restoration_dir/restore.sh" "$restoration_dir/restore.toml" ||
    ! chmod 755 "$shim_tmp" || ! mv -f "$shim_tmp" "$SHIV_BIN_DIR/$name"; then
    rm -f "$shim_tmp"
    rm -rf "$restoration_dir"
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
    ln -sf "$name" "$SHIV_BIN_DIR/$alias" || return 1
  done
}

# Compare the generated header as data, never source or eval an installed shim.
# REPO is followed by DEFAULT_TASK in both current and legacy headers.
shiv_shim_matches_repo() {
  local shim_file="$1" expected_repo="$2"
  local shim_source repo_assignment expected_assignment

  shim_source=$(< "$shim_file") || return 1
  case "$shim_source" in
    *$'\nREPO='*$'\nDEFAULT_TASK='*) ;;
    *) return 1 ;;
  esac

  repo_assignment=${shim_source#*$'\nREPO='}
  repo_assignment=${repo_assignment%%$'\nDEFAULT_TASK='*}
  expected_assignment=$(shiv_shell_quote "$expected_repo") || return 1
  [ "$repo_assignment" = "$expected_assignment" ] && return 0

  expected_assignment=$(shiv_double_quote_escape "$expected_repo") || return 1
  [ "$repo_assignment" = "\"$expected_assignment\"" ]
}

# Refresh every generated artifact for a registered package.
shiv_refresh_package() {
  local name="$1" repo_dir="$2" require_cache_refresh="${3:-false}"
  local aliases=()
  local alias_output

  shiv_create_shim "$name" "$repo_dir" || return 1
  shiv_cache_tasks "$name" "$repo_dir" "$require_cache_refresh" || return 1
  shiv_cache_task_map "$name" "$repo_dir" "$require_cache_refresh" || return 1

  alias_output=$(shiv_registry_aliases "$name") || return 1
  while IFS= read -r alias; do
    [ -n "$alias" ] && aliases+=("$alias")
  done <<< "$alias_output"

  if [ "${#aliases[@]}" -gt 0 ]; then
    shiv_create_alias_symlinks "$name" "${aliases[@]}" || return 1
  fi
}

# Escape shell-active content for a generated double-quoted value.
shiv_double_quote_escape() {
  local value="$1"
  value=${value//\\/\\\\}
  value=${value//\"/\\\"}
  value=${value//\$/\\\$}
  value=${value//\`/\\\`}
  printf '%s' "$value"
}

# Read REPO from a generated shim without evaluating its shell source.
shiv_read_generated_repo() {
  local shim="$1" value result="" char next
  value=$(sed -n 's/^REPO="\(.*\)"$/\1/p' "$shim")
  [ -n "$value" ] || return 1

  while [ -n "$value" ]; do
    char=${value%"${value#?}"}
    value=${value#?}

    if [ "$char" != "\\" ]; then
      result="${result}${char}"
      continue
    fi

    [ -n "$value" ] || return 1
    next=${value%"${value#?}"}
    value=${value#?}
    case "$next" in
      \\|'"'|'$'|'`') result="${result}${next}" ;;
      *) result="${result}\\${next}" ;;
    esac
  done

  printf '%s\n' "$result"
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
