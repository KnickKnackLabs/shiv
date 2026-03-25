#!/usr/bin/env bash
# shiv space-to-colon resolution — pure matching logic
#
# Given a task map file and user arguments, resolves space-separated
# words into a colon-joined mise task name plus remaining arguments.
#
# Usage:
#   shiv_resolve_task <task_map_file> [args...]
#
# Output (stdout):
#   Line 1: resolved task name (colon-joined, e.g. "agent:message")
#   Line 2: remaining args (space-separated, may be empty)
#
# Exit codes:
#   0 — matched unambiguously
#   1 — ambiguous (error message printed to stderr)
#   2 — no match found (caller should fall through to mise)

# Resolve space-separated arguments to a colon-joined task name.
# Pure function — reads from the task map file, no side effects.
shiv_resolve_task() {
  local task_map_file="$1"
  shift
  local args=("$@")

  # No args — nothing to resolve
  if [ ${#args[@]} -eq 0 ]; then
    return 2
  fi

  # No task map — can't resolve
  if [ ! -f "$task_map_file" ]; then
    return 2
  fi

  # ------------------------------------------------------------------
  # Case 1: explicit -- delimiter
  # Everything before -- is the task path, everything after is args.
  # ------------------------------------------------------------------
  local dash_pos=-1
  for i in "${!args[@]}"; do
    if [ "${args[$i]}" = "--" ]; then
      dash_pos=$i
      break
    fi
  done

  if [ "$dash_pos" -ge 0 ]; then
    # Words before --
    local task_words=("${args[@]:0:$dash_pos}")
    # Words after --
    local remaining_args=()
    if [ $((dash_pos + 1)) -lt ${#args[@]} ]; then
      remaining_args=("${args[@]:$((dash_pos + 1))}")
    fi

    # Must have at least one task word
    if [ ${#task_words[@]} -eq 0 ]; then
      return 2
    fi

    # Join task words with colons
    local task
    task=$(IFS=":"; echo "${task_words[*]}")

    # Verify the task exists in the map (join with spaces for lookup)
    local task_spaced
    task_spaced=$(IFS=" "; echo "${task_words[*]}")
    if grep -qxF "$task_spaced" "$task_map_file"; then
      echo "$task"
      echo "${remaining_args[*]}"
      return 0
    fi

    # -- was used but the task path doesn't exist — let mise handle it
    return 2
  fi

  # ------------------------------------------------------------------
  # Case 2: longest-prefix match (no --)
  # Try the longest prefix of input words first. The first match wins.
  # ------------------------------------------------------------------
  local n=${#args[@]}
  local best_len=0

  # Find the longest matching prefix
  for (( len=n; len>=1; len-- )); do
    local candidate
    candidate=$(IFS=" "; echo "${args[*]:0:$len}")
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
  # Case 3: ambiguity detection
  # If we matched at length N, check if a shorter prefix also matches.
  # That means the user's input is ambiguous.
  # ------------------------------------------------------------------
  local shorter_match=0
  local shorter_len=0
  for (( len=best_len-1; len>=1; len-- )); do
    local candidate
    candidate=$(IFS=" "; echo "${args[*]:0:$len}")
    if grep -qxF "$candidate" "$task_map_file"; then
      shorter_match=1
      shorter_len=$len
      break
    fi
  done

  if [ "$shorter_match" -eq 1 ]; then
    # Ambiguous — the longest match consumed all remaining words as task path,
    # but a shorter match exists that would leave some as args.
    local long_task_spaced
    long_task_spaced=$(IFS=" "; echo "${args[*]:0:$best_len}")
    local long_task
    long_task=$(IFS=":"; echo "${args[*]:0:$best_len}")

    local short_task_spaced
    short_task_spaced=$(IFS=" "; echo "${args[*]:0:$shorter_len}")
    local short_task
    short_task=$(IFS=":"; echo "${args[*]:0:$shorter_len}")

    local short_remaining=("${args[@]:$shorter_len}")

    local name
    name=$(basename "$task_map_file")

    echo "Ambiguous: '${args[*]}' matches task '$long_task', but '$short_task' is also a task." >&2
    echo "Use -- to disambiguate:" >&2
    echo "  $name ${short_task_spaced} -- ${short_remaining[*]}     (task '$short_task', args: ${short_remaining[*]})" >&2
    echo "  $name ${long_task_spaced} --     (task '$long_task', no args)" >&2
    return 1
  fi

  # ------------------------------------------------------------------
  # Unambiguous match — return task + remaining args
  # ------------------------------------------------------------------
  local task
  task=$(IFS=":"; echo "${args[*]:0:$best_len}")
  local remaining_args=("${args[@]:$best_len}")

  echo "$task"
  echo "${remaining_args[*]}"
  return 0
}
