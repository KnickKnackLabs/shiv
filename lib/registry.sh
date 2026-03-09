#!/usr/bin/env bash
# shiv registry — manages the package registry
#
# Registry format (registry.json):
#   {
#     "package-name": {
#       "path": "/absolute/path/to/repo",
#       "aliases": ["alias1", "alias2"]
#     }
#   }
#
# The "aliases" key is optional — omitted when there are none.

SHIV_CONFIG_DIR="${SHIV_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/shiv}"
SHIV_REGISTRY="${SHIV_REGISTRY:-$SHIV_CONFIG_DIR/registry.json}"

# Ensure registry exists
shiv_init_registry() {
  mkdir -p "$(dirname "$SHIV_REGISTRY")"
  if [ ! -f "$SHIV_REGISTRY" ]; then
    echo '{}' > "$SHIV_REGISTRY"
  fi
}

# Register a package in the registry
# Usage: shiv_register <name> <path> [alias1 alias2 ...]
shiv_register() {
  local name="$1" repo_dir="$2"
  shift 2
  local aliases=("$@")

  shiv_init_registry

  local tmp
  if [ ${#aliases[@]} -eq 0 ]; then
    tmp=$(jq --arg n "$name" --arg p "$repo_dir" \
      '.[$n] = {"path": $p}' "$SHIV_REGISTRY")
  else
    local aliases_json
    aliases_json=$(printf '%s\n' "${aliases[@]}" | jq -R . | jq -s .)
    tmp=$(jq --arg n "$name" --arg p "$repo_dir" --argjson a "$aliases_json" \
      '.[$n] = {"path": $p, "aliases": $a}' "$SHIV_REGISTRY")
  fi
  echo "$tmp" > "$SHIV_REGISTRY"
}

# Unregister a package
shiv_unregister() {
  local name="$1"
  shiv_init_registry
  local tmp
  tmp=$(jq --arg n "$name" 'del(.[$n])' "$SHIV_REGISTRY")
  echo "$tmp" > "$SHIV_REGISTRY"
}

# Get the path for a package
shiv_registry_path() {
  local name="$1"
  jq -r --arg n "$name" '.[$n].path // empty' "$SHIV_REGISTRY"
}

# Get aliases for a package (one per line)
shiv_registry_aliases() {
  local name="$1"
  jq -r --arg n "$name" '.[$n].aliases // [] | .[]' "$SHIV_REGISTRY"
}

# Set aliases for an existing package
shiv_registry_set_aliases() {
  local name="$1"
  shift
  local aliases=("$@")

  local tmp
  if [ ${#aliases[@]} -eq 0 ]; then
    tmp=$(jq --arg n "$name" '.[$n] |= del(.aliases)' "$SHIV_REGISTRY")
  else
    local aliases_json
    aliases_json=$(printf '%s\n' "${aliases[@]}" | jq -R . | jq -s .)
    tmp=$(jq --arg n "$name" --argjson a "$aliases_json" \
      '.[$n].aliases = $a' "$SHIV_REGISTRY")
  fi
  echo "$tmp" > "$SHIV_REGISTRY"
}

# Iterate all entries as "name<TAB>path" lines
shiv_registry_entries() {
  jq -r 'to_entries[] | "\(.key)\t\(.value.path)"' "$SHIV_REGISTRY"
}

# Resolve a name that might be a package name or an alias
# Prints the package name, or empty if not found
shiv_registry_resolve() {
  local name="$1"

  # Direct match — it's a package name
  local path
  path=$(shiv_registry_path "$name")
  if [ -n "$path" ]; then
    echo "$name"
    return 0
  fi

  # Search aliases
  jq -r --arg n "$name" \
    'to_entries[] | select(.value.aliases // [] | index($n)) | .key' \
    "$SHIV_REGISTRY" | head -1
}
