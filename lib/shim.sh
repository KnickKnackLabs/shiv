#!/usr/bin/env bash
# shiv shim generation — the core mechanism
#
# This file contains the functions that create and manage shims.
# It's sourced by shiv's own tasks and can be used standalone.

SHIV_BIN_DIR="$HOME/.local/bin"
SHIV_DATA_DIR="$HOME/.local/share/shiv"
SHIV_PACKAGES_DIR="$SHIV_DATA_DIR/packages"
SHIV_REGISTRY="$HOME/.config/shiv/registry.json"
SHIV_SOURCES_DIR="$HOME/.config/shiv/sources"

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

# Ensure registry exists
shiv_init_registry() {
  mkdir -p "$(dirname "$SHIV_REGISTRY")"
  if [ ! -f "$SHIV_REGISTRY" ]; then
    echo '{}' > "$SHIV_REGISTRY"
  fi
}

# Create a shim for a tool
shiv_create_shim() {
  local name="$1" repo_dir="$2"
  mkdir -p "$SHIV_BIN_DIR"
  cat > "$SHIV_BIN_DIR/$name" <<SCRIPT
#!/usr/bin/env bash
# managed by shiv
REPO="$repo_dir"
if [ ! -d "\$REPO" ]; then
  echo "$name: repo not found at \$REPO" >&2
  echo "$name: run 'shiv doctor' to diagnose" >&2
  exit 1
fi
exec mise -C "\$REPO" run "\$@"
SCRIPT
  chmod +x "$SHIV_BIN_DIR/$name"
}

# Register a tool in the registry
shiv_register() {
  local name="$1" repo_dir="$2"
  shiv_init_registry
  local tmp
  tmp=$(jq --arg n "$name" --arg p "$repo_dir" '. + {($n): $p}' "$SHIV_REGISTRY")
  echo "$tmp" > "$SHIV_REGISTRY"
}

# Unregister a tool
shiv_unregister() {
  local name="$1"
  shiv_init_registry
  local tmp
  tmp=$(jq --arg n "$name" 'del(.[$n])' "$SHIV_REGISTRY")
  echo "$tmp" > "$SHIV_REGISTRY"
}

# Output shell config (PATH + alias) for a tool
shiv_shell_config() {
  local name="$1" repo_dir="$2"
  echo "alias $name='mise -C \"$repo_dir\" run'"
}

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
  local seen=()

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
