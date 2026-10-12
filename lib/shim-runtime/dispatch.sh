#!/usr/bin/env bash
# Embedded entry point: preserve caller settings, then dispatch package tasks.

_shiv_check_repo
shiv_snapshot_caller_env "$SHIV_CALLER_OWNER" "$SHIV_SETTING_PREFIX" || exit 1
export "SHIV_CALLER_OWNER_${SHIV_DIRECTORY_KEY}=$SHIV_CALLER_OWNER"
export "$SHIV_CALLER_PWD_VAR=$PWD"
_shiv_check_cwd "$@"

case "${1:-}" in
  --help|-h|help)
    _shiv_handle_help "${1:-help}"
    ;;
  tasks)
    _shiv_handle_tasks "$@"
    ;;
  *)
    # --- Default task handling ---
    # No args: run default task directly.
    if [ -n "$DEFAULT_TASK" ] && [ -z "${1:-}" ]; then
      _shiv_exec_package_mise run -q "$DEFAULT_TASK"
    fi

    # "--" as first arg: explicit disambiguation — send everything
    # after "--" to the default task.
    if [ -n "$DEFAULT_TASK" ] && [ "${1:-}" = "--" ]; then
      shift
      if [ $# -gt 0 ]; then
        _shiv_exec_package_mise run -q "$DEFAULT_TASK" "$@"
      else
        _shiv_exec_package_mise run -q "$DEFAULT_TASK"
      fi
    fi

    # Check if "--" is present in args (user is disambiguating).
    _shiv_has_dash=false
    for _shiv_arg in "$@"; do
      if [ "$_shiv_arg" = "--" ]; then
        _shiv_has_dash=true
        break
      fi
    done

    # Space-to-colon resolution
    _shiv_ensure_task_map
    shiv_resolve_task "$SHIV_PACKAGE_NAME" "$SHIV_TASK_MAP" "$@"
    _shiv_rc=$?
    if [ "$_shiv_rc" -eq 0 ]; then
      # Resolved a subtask. If a default task also exists and the user
      # didn't use "--" to disambiguate, this is ambiguous.
      if [ -n "$DEFAULT_TASK" ] && [ "$_shiv_has_dash" = "false" ]; then
        echo "Ambiguous: '$*' could be:" >&2
        echo "  task '$SHIV_RESOLVED_TASK' with args: ${SHIV_RESOLVED_ARGS[*]:-<none>}" >&2
        echo "  default task with args: $*" >&2
        echo "Use -- to disambiguate:" >&2
        echo "  $SHIV_PACKAGE_NAME ${SHIV_RESOLVED_TASK//:/ } -- ${SHIV_RESOLVED_ARGS[*]}     (task '$SHIV_RESOLVED_TASK')" >&2
        echo "  $SHIV_PACKAGE_NAME -- $*     (default task)" >&2
        exit 1
      fi
      # Guard: only expand SHIV_RESOLVED_ARGS when non-empty.
      # bash <4.4 treats "${empty_array[@]}" as unbound under set -u.
      if [ ${#SHIV_RESOLVED_ARGS[@]} -gt 0 ]; then
        _shiv_exec_package_mise run -q "$SHIV_RESOLVED_TASK" "${SHIV_RESOLVED_ARGS[@]}"
      else
        _shiv_exec_package_mise run -q "$SHIV_RESOLVED_TASK"
      fi
    elif [ "$_shiv_rc" -eq 1 ]; then
      exit 1  # ambiguous — error already printed to stderr
    fi
    # rc=2 or no task map: fall through to default task or mise
    if [ -n "$DEFAULT_TASK" ]; then
      _shiv_exec_package_mise run -q "$DEFAULT_TASK" "$@"
    fi
    _shiv_exec_package_mise run -q "$@"
    ;;
esac
