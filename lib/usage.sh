#!/usr/bin/env bash
# shiv task help — renders the help mise skips
#
# mise renders a task's #USAGE help for `mise run <task> --help`, but when the
# flag arrives after `--` it consumes the flag without rendering help and
# without binding any arguments. A task that declares a required arg then
# starts with `usage_<arg>` unset and dies under `set -u` before it can report
# anything useful. The raw argv still reaches the task, so a task can spot the
# flag itself and ask mise for the help it skipped.

SHIV_USAGE_REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Render mise's generated help for the calling task when its argv asks for it.
# Call from a task, before reading any usage_* variable:
#
#   shiv_help_guard "$@"
shiv_help_guard() {
  local arg task

  for arg in "$@"; do
    [ "$arg" = "-h" ] || [ "$arg" = "--help" ] || continue

    task=$(basename "$0")

    # Only re-enter once. If mise runs the task again instead of rendering
    # help, report a usage error rather than looping.
    if [ -n "${SHIV_HELP_GUARD:-}" ]; then
      echo "shiv: could not render help for '$task'" >&2
      return 1
    fi

    export SHIV_HELP_GUARD=1
    mise -C "$SHIV_USAGE_REPO_DIR" run "$task" --help
    exit
  done
}
