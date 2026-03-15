#!/usr/bin/env bash
# shiv sources — package index lookup
# Depends on SHIV_CONFIG_DIR being set (by registry.sh, sourced first)

SHIV_SOURCES_DIR="${SHIV_SOURCES_DIR:-$SHIV_CONFIG_DIR/sources}"

# SHIV_SOURCES: comma-delimited list of sources.json files to search.
# If not set by the user, auto-discover from SHIV_SOURCES_DIR.
if [ -z "$SHIV_SOURCES" ] && [ -d "$SHIV_SOURCES_DIR" ]; then
  SHIV_SOURCES=""
  for _sf in "$SHIV_SOURCES_DIR"/*.json; do
    [ -f "$_sf" ] || continue
    SHIV_SOURCES="${SHIV_SOURCES:+$SHIV_SOURCES,}$_sf"
  done
  unset _sf
fi

# Look up a package name across all sources (SHIV_SOURCES, then repo fallback)
# Prints the GitHub repo slug (e.g. "KnickKnackLabs/shimmer") or returns 1
shiv_lookup() {
  local name="$1" result=""

  if [ -n "$SHIV_SOURCES" ]; then
    IFS=',' read -ra _source_files <<< "$SHIV_SOURCES"
    for sf in "${_source_files[@]}"; do
      sf="${sf## }"; sf="${sf%% }"
      [ -f "$sf" ] || continue
      result=$(jq -r --arg n "$name" '.[$n] // empty' "$sf")
      [ -n "$result" ] && echo "$result" && return 0
    done
  fi

  # Fallback: repo-level sources.json
  local repo_sources
  repo_sources="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/sources.json"
  if [ -f "$repo_sources" ]; then
    result=$(jq -r --arg n "$name" '.[$n] // empty' "$repo_sources")
    [ -n "$result" ] && echo "$result" && return 0
  fi

  return 1
}

# List all available packages across all sources
shiv_list_sources() {
  if [ -n "$SHIV_SOURCES" ]; then
    IFS=',' read -ra _source_files <<< "$SHIV_SOURCES"
    for sf in "${_source_files[@]}"; do
      sf="${sf## }"; sf="${sf%% }"
      [ -f "$sf" ] || continue
      jq -r 'to_entries[] | "\(.key) \(.value)"' "$sf"
    done
  fi

  local repo_sources
  repo_sources="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/sources.json"
  if [ -f "$repo_sources" ]; then
    jq -r 'to_entries[] | "\(.key) \(.value)"' "$repo_sources"
  fi
}

# Detect whether a ref is a tag, branch, or commit SHA
# Usage: shiv_detect_ref_type <github-repo-slug> <ref>
# Prints "tag", "branch", or "commit" to stdout; returns 1 if unknown
shiv_detect_ref_type() {
  local gh_repo="$1" ref="$2"

  # Check remote refs via ls-remote first (handles tags/branches, including
  # hex-named ones like "deadbeef" that would otherwise match the SHA pattern)
  local ls_output ls_exit
  ls_output=$(git ls-remote "https://github.com/${gh_repo}.git" "$ref" 2>&1)
  ls_exit=$?

  if [ "$ls_exit" -eq 0 ] && [ -n "$ls_output" ]; then
    if echo "$ls_output" | grep -q "refs/tags/"; then
      echo "tag"
    elif echo "$ls_output" | grep -q "refs/heads/"; then
      echo "branch"
    else
      echo "Error: ref '$ref' has unexpected type in $gh_repo" >&2
      return 1
    fi
    return 0
  fi

  # ls-remote didn't find a named ref — check if it looks like a commit SHA
  if [[ "$ref" =~ ^[0-9a-f]{7,40}$ ]]; then
    echo "commit"
    return 0
  fi

  # Neither a named ref nor a SHA — report the error
  if [ "$ls_exit" -ne 0 ]; then
    echo "Error: failed to query refs for $gh_repo" >&2
    echo "$ls_output" | sed 's/^/  /' >&2
  else
    echo "Error: ref '$ref' not found in $gh_repo" >&2
  fi
  return 1
}
