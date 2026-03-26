#!/usr/bin/env bash
# shiv space-to-colon resolution — pure matching logic
#
# Given a tool name, task map file, and user arguments, resolves
# space-separated words into a colon-joined mise task name plus
# remaining arguments.
#
# Usage:
#   shiv_resolve_task <tool_name> <task_map_file> [args...]
#
# Output (via variables — no stdout):
#   SHIV_RESOLVED_TASK  — colon-joined task name (e.g. "agent:message")
#   SHIV_RESOLVED_ARGS  — array of remaining arguments (preserves quoting)
#
# Exit codes:
#   0 — matched unambiguously
#   1 — ambiguous (error message printed to stderr)
#   2 — no match found (caller should fall through to mise)

# Resolve space-separated arguments to a colon-joined task name.
# Pure function — reads from the task map file, no side effects beyond
# setting SHIV_RESOLVED_TASK and SHIV_RESOLVED_ARGS.
#
# Performance: the matching loop spawns a grep per prefix length, making
# it O(n×m) where n = number of input words and m = task map size. This
# is fine for typical task maps (<100 entries) but could be replaced with
# a single-pass approach if maps grow large. An associative array (bash
# declare -A) would eliminate fork overhead but requires bash 4.0+; the
# grep approach maintains compatibility with bash 3.2 (macOS default).
shiv_resolve_task() {
  local tool_name="$1"
  local task_map_file="$2"
  shift 2
  local args=("$@")

  SHIV_RESOLVED_TASK=""
  SHIV_RESOLVED_ARGS=()

  # No args — nothing to resolve
  if [ ${#args[@]} -eq 0 ]; then
    return 2
  fi

  # No task map — can't resolve
  if [ ! -f "$task_map_file" ]; then
    return 2
  fi

  # ------------------------------------------------------------------
  # Split at -- if present.
  # Words before -- are task candidates; words after are post-dash args.
  # Whether -- is consumed (disambiguation) or passed through to mise
  # depends on whether the input is ambiguous — decided below.
  # ------------------------------------------------------------------
  local dash_pos=-1
  for i in "${!args[@]}"; do
    if [ "${args[$i]}" = "--" ]; then
      dash_pos=$i
      break
    fi
  done

  local task_candidates=()
  local post_dash_args=()

  if [ "$dash_pos" -ge 0 ]; then
    if [ "$dash_pos" -gt 0 ]; then
      task_candidates=("${args[@]:0:$dash_pos}")
    fi
    if [ $((dash_pos + 1)) -lt ${#args[@]} ]; then
      post_dash_args=("${args[@]:$((dash_pos + 1))}")
    fi
  else
    task_candidates=("${args[@]}")
  fi

  # Must have at least one task candidate word
  if [ ${#task_candidates[@]} -eq 0 ]; then
    return 2
  fi

  # ------------------------------------------------------------------
  # Longest-prefix match on task candidates
  # ------------------------------------------------------------------
  local n=${#task_candidates[@]}
  local best_len=0

  for (( len=n; len>=1; len-- )); do
    local candidate
    candidate=$(IFS=" "; echo "${task_candidates[*]:0:$len}")
    if grep -qxF "$candidate" "$task_map_file"; then
      best_len=$len
      break
    fi
  done

  # No match at any prefix length
  if [ "$best_len" -eq 0 ]; then
    return 2
  fi

  # ------------------------------------------------------------------
  # Ambiguity detection
  # If we matched at length N, check if a shorter prefix also matches.
  # ------------------------------------------------------------------
  local shorter_match=0
  local shorter_len=0
  for (( len=best_len-1; len>=1; len-- )); do
    local candidate
    candidate=$(IFS=" "; echo "${task_candidates[*]:0:$len}")
    if grep -qxF "$candidate" "$task_map_file"; then
      shorter_match=1
      shorter_len=$len
      break
    fi
  done

  if [ "$shorter_match" -eq 1 ]; then
    # ------------------------------------------------------------------
    # Ambiguous input. If -- is present, use it to disambiguate:
    # all task_candidates become the task name, post_dash_args are args.
    # If no --, error with guidance.
    # ------------------------------------------------------------------
    if [ "$dash_pos" -ge 0 ]; then
      local task_spaced
      task_spaced=$(IFS=" "; echo "${task_candidates[*]}")
      if grep -qxF "$task_spaced" "$task_map_file"; then
        SHIV_RESOLVED_TASK=$(IFS=":"; echo "${task_candidates[*]}")
        SHIV_RESOLVED_ARGS=("${post_dash_args[@]}")
        return 0
      fi
      # -- was used but the full candidate path doesn't exist
      return 2
    fi

    local long_task_spaced
    long_task_spaced=$(IFS=" "; echo "${task_candidates[*]:0:$best_len}")
    local long_task
    long_task=$(IFS=":"; echo "${task_candidates[*]:0:$best_len}")

    local short_task_spaced
    short_task_spaced=$(IFS=" "; echo "${task_candidates[*]:0:$shorter_len}")
    local short_task
    short_task=$(IFS=":"; echo "${task_candidates[*]:0:$shorter_len}")

    local short_remaining=("${task_candidates[@]:$shorter_len}")

    echo "Ambiguous: '${task_candidates[*]}' matches task '$long_task', but '$short_task' is also a task." >&2
    echo "Use -- to disambiguate:" >&2
    echo "  $tool_name ${short_task_spaced} -- ${short_remaining[*]}     (task '$short_task', args: ${short_remaining[*]})" >&2
    echo "  $tool_name ${long_task_spaced} --     (task '$long_task', no args)" >&2
    return 1
  fi

  # ------------------------------------------------------------------
  # Unambiguous match.
  # Remaining args = unmatched suffix of task_candidates.
  # If -- was present, pass it through along with post_dash_args
  # (preserving identical behavior to the colon-separated form).
  # ------------------------------------------------------------------
  SHIV_RESOLVED_TASK=$(IFS=":"; echo "${task_candidates[*]:0:$best_len}")

  local remaining=("${task_candidates[@]:$best_len}")
  if [ "$dash_pos" -ge 0 ]; then
    remaining+=("--")
    if [ ${#post_dash_args[@]} -gt 0 ]; then
      remaining+=("${post_dash_args[@]}")
    fi
  fi
  SHIV_RESOLVED_ARGS=("${remaining[@]}")
  return 0
}
