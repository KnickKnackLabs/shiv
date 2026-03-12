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

  # Commit SHA pattern: 7-40 lowercase hex characters
  if [[ "$ref" =~ ^[0-9a-f]{7,40}$ ]]; then
    echo "commit"
    return 0
  fi

  # Check remote refs via ls-remote
  local ls_output
  ls_output=$(git ls-remote "https://github.com/${gh_repo}.git" "$ref" 2>/dev/null)

  if [ -z "$ls_output" ]; then
    echo "Error: ref '$ref' not found in $gh_repo" >&2
    return 1
  fi

  if echo "$ls_output" | grep -q "refs/tags/"; then
    echo "tag"
  elif echo "$ls_output" | grep -q "refs/heads/"; then
    echo "branch"
  else
    echo "Error: ref '$ref' has unexpected type in $gh_repo" >&2
    return 1
  fi
}
