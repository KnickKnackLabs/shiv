#!/usr/bin/env bash
# shiv sources — package index lookup

SHIV_CONFIG_DIR="${SHIV_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/shiv}"
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
