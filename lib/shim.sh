#!/usr/bin/env bash
# shiv shim generation — the core mechanism
#
# This file creates and manages shims, and sources the other lib files
# for registry, cache, and source operations.

REPO_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$REPO_LIB_DIR/registry.sh"
source "$REPO_LIB_DIR/cache.sh"
source "$REPO_LIB_DIR/sources.sh"

SHIV_BIN_DIR="${SHIV_BIN_DIR:-$HOME/.local/bin}"
SHIV_DATA_DIR="${SHIV_DATA_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/shiv}"
SHIV_PACKAGES_DIR="${SHIV_PACKAGES_DIR:-$SHIV_DATA_DIR/packages}"

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
if [ "\$(basename "\$PWD")" = "$name" ] && [ "\$PWD" != "$repo_dir" ]; then
  echo "$name: warning: you're in a directory called '$name' but running the shiv-installed copy" >&2
  echo "$name: shiv package: $repo_dir" >&2
  echo "$name: current dir: \$PWD" >&2
  echo "$name: to run from this directory instead: mise run \$*" >&2
  echo "" >&2
fi
case "\${1:-}" in
  --help|-h|help)
    exec mise -C "\$REPO" tasks
    ;;
  *)
    exec mise -C "\$REPO" run -q "\$@"
    ;;
esac
SCRIPT
  chmod +x "$SHIV_BIN_DIR/$name"
}

# Create alias symlinks for a package (relative, same directory)
shiv_create_alias_symlinks() {
  local name="$1"
  shift
  local aliases=("$@")
  for alias in "${aliases[@]}"; do
    ln -sf "$name" "$SHIV_BIN_DIR/$alias"
  done
}

# Remove alias symlinks for a package (only if they point to the expected target)
shiv_remove_alias_symlinks() {
  local name="$1"
  shift
  local aliases=("$@")
  for alias in "${aliases[@]}"; do
    if [ -L "$SHIV_BIN_DIR/$alias" ] && [ "$(readlink "$SHIV_BIN_DIR/$alias")" = "$name" ]; then
      rm -f "$SHIV_BIN_DIR/$alias"
    fi
  done
}
