#!/usr/bin/env bats
# shiv registry test suite

REPO_DIR="$BATS_TEST_DIRNAME/.."

setup() {
  source "$REPO_DIR/lib/shim.sh"

  export TEST_HOME="$BATS_TMPDIR/shiv-test-$$"
  mkdir -p "$TEST_HOME"

  export SHIV_BIN_DIR="$TEST_HOME/.local/bin"
  export SHIV_DATA_DIR="$TEST_HOME/.local/share/shiv"
  export SHIV_PACKAGES_DIR="$SHIV_DATA_DIR/packages"
  export SHIV_CONFIG_DIR="$TEST_HOME/.config/shiv"
  export SHIV_CACHE_DIR="$TEST_HOME/.cache/shiv"
  export SHIV_REGISTRY="$SHIV_CONFIG_DIR/registry.json"
  export SHIV_SOURCES_DIR="$SHIV_CONFIG_DIR/sources"

  shiv_init_registry
}

teardown() {
  rm -rf "$TEST_HOME"
}

# ============================================================================
# Registry format
# ============================================================================

@test "registry: init creates empty object" {
  [ -f "$SHIV_REGISTRY" ]
  [ "$(jq 'length' "$SHIV_REGISTRY")" -eq 0 ]
}

@test "registry: register stores path as object" {
  shiv_register "mypackage" "/path/to/repo"
  jq -e '.mypackage.path == "/path/to/repo"' "$SHIV_REGISTRY"
}

@test "registry: register without aliases omits aliases key" {
  shiv_register "mypackage" "/path/to/repo"
  run jq -e '.mypackage | has("aliases")' "$SHIV_REGISTRY"
  [ "$status" -ne 0 ]
}

@test "registry: register with aliases stores them" {
  shiv_register "wallpapers" "/path/to/wallpapers" "wp" "walls"
  jq -e '.wallpapers.aliases == ["wp", "walls"]' "$SHIV_REGISTRY"
}

@test "registry: unregister removes entry" {
  shiv_register "mypackage" "/path/to/repo"
  shiv_unregister "mypackage"
  run jq -e '.mypackage' "$SHIV_REGISTRY"
  [ "$status" -ne 0 ]
}

# ============================================================================
# Registry helpers
# ============================================================================

@test "registry: shiv_registry_path returns path" {
  shiv_register "mypackage" "/path/to/repo"
  [ "$(shiv_registry_path "mypackage")" = "/path/to/repo" ]
}

@test "registry: shiv_registry_path returns empty for missing" {
  [ -z "$(shiv_registry_path "nonexistent")" ]
}

@test "registry: shiv_registry_aliases returns aliases" {
  shiv_register "wallpapers" "/path/to/wallpapers" "wp" "walls"
  mapfile -t aliases < <(shiv_registry_aliases "wallpapers")
  [ "${#aliases[@]}" -eq 2 ]
  [ "${aliases[0]}" = "wp" ]
  [ "${aliases[1]}" = "walls" ]
}

@test "registry: shiv_registry_aliases returns empty when none" {
  shiv_register "mypackage" "/path/to/repo"
  [ -z "$(shiv_registry_aliases "mypackage")" ]
}

@test "registry: shiv_registry_entries outputs name-tab-path" {
  shiv_register "alpha" "/path/a"
  shiv_register "beta" "/path/b"
  local count=0
  shiv_registry_entries | while IFS=$'\t' read -r name path; do
    [ -n "$name" ] && [ -n "$path" ]
    count=$((count + 1))
  done
  [ "$(shiv_registry_entries | wc -l | tr -d ' ')" -eq 2 ]
}

@test "registry: shiv_registry_set_aliases updates aliases" {
  shiv_register "wallpapers" "/path/to/wallpapers" "wp"
  shiv_registry_set_aliases "wallpapers" "wp" "walls" "w"
  mapfile -t aliases < <(shiv_registry_aliases "wallpapers")
  [ "${#aliases[@]}" -eq 3 ]
}

@test "registry: shiv_registry_set_aliases with no args removes aliases" {
  shiv_register "wallpapers" "/path/to/wallpapers" "wp"
  shiv_registry_set_aliases "wallpapers"
  run jq -e '.wallpapers | has("aliases")' "$SHIV_REGISTRY"
  [ "$status" -ne 0 ]
}

# ============================================================================
# Resolve (package name or alias)
# ============================================================================

@test "resolve: finds by package name" {
  shiv_register "wallpapers" "/path/to/wallpapers"
  [ "$(shiv_registry_resolve "wallpapers")" = "wallpapers" ]
}

@test "resolve: finds by alias" {
  shiv_register "wallpapers" "/path/to/wallpapers" "wp"
  [ "$(shiv_registry_resolve "wp")" = "wallpapers" ]
}

@test "resolve: returns empty for unknown" {
  [ -z "$(shiv_registry_resolve "nonexistent")" ]
}

# ============================================================================
# Alias symlinks
# ============================================================================

@test "symlinks: shiv_create_alias_symlinks creates symlinks" {
  mkdir -p "$SHIV_BIN_DIR"
  shiv_create_shim "wallpapers" "$REPO_DIR"
  shiv_create_alias_symlinks "wallpapers" "wp" "walls"
  [ -L "$SHIV_BIN_DIR/wp" ]
  [ -L "$SHIV_BIN_DIR/walls" ]
  [ "$(readlink "$SHIV_BIN_DIR/wp")" = "$SHIV_BIN_DIR/wallpapers" ]
}

@test "symlinks: shiv_remove_alias_symlinks cleans up" {
  mkdir -p "$SHIV_BIN_DIR"
  shiv_create_shim "wallpapers" "$REPO_DIR"
  shiv_create_alias_symlinks "wallpapers" "wp"
  [ -L "$SHIV_BIN_DIR/wp" ]
  shiv_remove_alias_symlinks "wallpapers" "wp"
  [ ! -L "$SHIV_BIN_DIR/wp" ]
}

@test "symlinks: alias symlink is executable" {
  mkdir -p "$SHIV_BIN_DIR"
  shiv_create_shim "wallpapers" "$REPO_DIR"
  shiv_create_alias_symlinks "wallpapers" "wp"
  [ -x "$SHIV_BIN_DIR/wp" ]
}

@test "symlinks: removing shim leaves symlinks dangling" {
  mkdir -p "$SHIV_BIN_DIR"
  shiv_create_shim "wallpapers" "$REPO_DIR"
  shiv_create_alias_symlinks "wallpapers" "wp"
  rm "$SHIV_BIN_DIR/wallpapers"
  # Symlink still exists but target is gone
  [ -L "$SHIV_BIN_DIR/wp" ]
  [ ! -e "$SHIV_BIN_DIR/wp" ]
}

# ============================================================================
# Schema validation
# ============================================================================

@test "schema: empty registry is valid" {
  if ! command -v check-jsonschema &>/dev/null; then
    skip "check-jsonschema not found"
  fi
  check-jsonschema --schemafile "$REPO_DIR/registry.schema.json" "$SHIV_REGISTRY"
}

@test "schema: registry with package is valid" {
  if ! command -v check-jsonschema &>/dev/null; then
    skip "check-jsonschema not found"
  fi
  shiv_register "wallpapers" "/path/to/wallpapers" "wp"
  check-jsonschema --schemafile "$REPO_DIR/registry.schema.json" "$SHIV_REGISTRY"
}

@test "schema: registry without aliases is valid" {
  if ! command -v check-jsonschema &>/dev/null; then
    skip "check-jsonschema not found"
  fi
  shiv_register "shimmer" "/path/to/shimmer"
  check-jsonschema --schemafile "$REPO_DIR/registry.schema.json" "$SHIV_REGISTRY"
}
