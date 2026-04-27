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

  # Check for alias collisions
  for alias in ${aliases[@]+"${aliases[@]}"}; do
    # Alias shadows an existing package name?
    if [ -n "$(shiv_registry_path "$alias")" ]; then
      echo "Error: alias '$alias' conflicts with existing package '$alias'" >&2
      return 1
    fi
    # Alias already claimed by another package?
    local owner
    owner=$(shiv_registry_resolve "$alias")
    if [ -n "$owner" ] && [ "$owner" != "$name" ]; then
      echo "Error: alias '$alias' already used by package '$owner'" >&2
      return 1
    fi
  done

  # Build aliases JSON (null if none)
  local aliases_json="null"
  if [ $# -gt 0 ]; then
    aliases_json=$(printf '%s\n' "${aliases[@]}" | jq -R . | jq -s .)
  fi

  local tmp
  tmp=$(jq --arg n "$name" --arg p "$repo_dir" \
    --arg r "${SHIV_REF:-}" \
    --argjson a "$aliases_json" \
    '.[$n] = ({"path": $p}
      + (if $r != "" then {"ref": $r} else {} end)
      + (if $a then {"aliases": $a} else {} end))' \
    "$SHIV_REGISTRY")
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

# Get the pinned ref for a package (empty if unpinned)
shiv_registry_ref() {
  local name="$1"
  jq -r --arg n "$name" '.[$n].ref // empty' "$SHIV_REGISTRY"
}

# Set aliases for an existing package
shiv_registry_set_aliases() {
  local name="$1"
  shift
  local aliases=("$@")

  # Check for alias collisions
  for alias in ${aliases[@]+"${aliases[@]}"}; do
    if [ -n "$(shiv_registry_path "$alias")" ]; then
      echo "Error: alias '$alias' conflicts with existing package '$alias'" >&2
      return 1
    fi
    local owner
    owner=$(shiv_registry_resolve "$alias")
    if [ -n "$owner" ] && [ "$owner" != "$name" ]; then
      echo "Error: alias '$alias' already used by package '$owner'" >&2
      return 1
    fi
  done

  local tmp
  if [ $# -eq 0 ]; then
    tmp=$(jq --arg n "$name" '.[$n] |= del(.aliases)' "$SHIV_REGISTRY")
  else
    local aliases_json
    aliases_json=$(printf '%s\n' "${aliases[@]}" | jq -R . | jq -s .)
    tmp=$(jq --arg n "$name" --argjson a "$aliases_json" \
      '.[$n].aliases = $a' "$SHIV_REGISTRY")
  fi
  echo "$tmp" > "$SHIV_REGISTRY"
}

# Iterate all entries as "name<TAB>path<TAB>ref" lines
shiv_registry_entries() {
  jq -r 'to_entries[] | "\(.key)\t\(.value.path)\t\(.value.ref // "")"' "$SHIV_REGISTRY"
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
