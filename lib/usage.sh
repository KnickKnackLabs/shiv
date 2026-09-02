#!/usr/bin/env bash
# shiv task help — renders the help mise skips
#
# mise consumes `--help` arriving after `--` without rendering help and without
# binding arguments, so the task dies on an unset usage_* variable instead. The
# raw argv still reaches the task, which is what makes this recoverable.

SHIV_USAGE_REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Call as `shiv_help_guard "$@"` before reading any usage_* variable.
shiv_help_guard() {
  local arg task

  for arg in "$@"; do
    [ "$arg" = "-h" ] || [ "$arg" = "--help" ] || continue

    task=$(basename "$0")

    # Re-entry means mise ran the task again instead of rendering help; stop.
    if [ -n "${SHIV_HELP_GUARD:-}" ]; then
      echo "shiv: could not render help for '$task'" >&2
      return 1
    fi

    export SHIV_HELP_GUARD=1
    mise -C "$SHIV_USAGE_REPO_DIR" run "$task" --help
    exit
  done
}
