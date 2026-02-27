#!/usr/bin/env bash
# shiv shim generation — the core mechanism
#
# This file contains the functions that create and manage shims.
# It's sourced by shiv's own tasks and can be used standalone.

SHIV_BIN_DIR="$HOME/.local/bin"
SHIV_DATA_DIR="$HOME/.local/share/shiv"
SHIV_PACKAGES_DIR="$SHIV_DATA_DIR/packages"
SHIV_REGISTRY="$HOME/.config/shiv/registry.json"
SHIV_SOURCES="$HOME/.config/shiv/sources.json"

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
export CALLER_PWD="\$PWD"
case "\${1:-}" in
  --help|-h|help)
    exec mise -C "\$REPO" tasks
    ;;
  *)
    exec mise -C "\$REPO" run "\$@"
    ;;
esac
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