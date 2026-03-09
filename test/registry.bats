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
  shiv_register "foo" "/path/to/foo"
  jq -e '.foo.path == "/path/to/foo"' "$SHIV_REGISTRY"
}

@test "registry: register without aliases omits aliases key" {
  shiv_register "foo" "/path/to/foo"
  run jq -e '.foo | has("aliases")' "$SHIV_REGISTRY"
  [ "$status" -ne 0 ]
}

@test "registry: register with aliases stores them" {
  shiv_register "foo" "/path/to/foo" "f" "fo"
  jq -e '.foo.aliases == ["f", "fo"]' "$SHIV_REGISTRY"
}

@test "registry: unregister removes entry" {
  shiv_register "foo" "/path/to/foo"
  shiv_unregister "foo"
  run jq -e '.foo' "$SHIV_REGISTRY"
  [ "$status" -ne 0 ]
}

# ============================================================================
# Registry helpers
# ============================================================================

@test "registry: shiv_registry_path returns path" {
  shiv_register "foo" "/path/to/foo"
  [ "$(shiv_registry_path "foo")" = "/path/to/foo" ]
}

@test "registry: shiv_registry_path returns empty for missing" {
  [ -z "$(shiv_registry_path "nonexistent")" ]
}

@test "registry: shiv_registry_aliases returns aliases" {
  shiv_register "foo" "/path/to/foo" "f" "fo"
  mapfile -t aliases < <(shiv_registry_aliases "foo")
  [ "${#aliases[@]}" -eq 2 ]
  [ "${aliases[0]}" = "f" ]
  [ "${aliases[1]}" = "fo" ]
}

@test "registry: shiv_registry_aliases returns empty when none" {
  shiv_register "foo" "/path/to/foo"
  [ -z "$(shiv_registry_aliases "foo")" ]
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
  shiv_register "foo" "/path/to/foo" "f"
  shiv_registry_set_aliases "foo" "f" "fo" "x"
  mapfile -t aliases < <(shiv_registry_aliases "foo")
  [ "${#aliases[@]}" -eq 3 ]
}

@test "registry: shiv_registry_set_aliases with no args removes aliases" {
  shiv_register "foo" "/path/to/foo" "f"
  shiv_registry_set_aliases "foo"
  run jq -e '.foo | has("aliases")' "$SHIV_REGISTRY"
  [ "$status" -ne 0 ]
}

# ============================================================================
# Resolve (package name or alias)
# ============================================================================

@test "resolve: finds by package name" {
  shiv_register "foo" "/path/to/foo"
  [ "$(shiv_registry_resolve "foo")" = "foo" ]
}

@test "resolve: finds by alias" {
  shiv_register "foo" "/path/to/foo" "f"
  [ "$(shiv_registry_resolve "f")" = "foo" ]
}

@test "resolve: returns empty for unknown" {
  [ -z "$(shiv_registry_resolve "nonexistent")" ]
}

# ============================================================================
# Alias symlinks
# ============================================================================

@test "symlinks: shiv_create_alias_symlinks creates symlinks" {
  mkdir -p "$SHIV_BIN_DIR"
  shiv_create_shim "foo" "$REPO_DIR"
  shiv_create_alias_symlinks "foo" "f" "fo"
  [ -L "$SHIV_BIN_DIR/f" ]
  [ -L "$SHIV_BIN_DIR/fo" ]
  [ "$(readlink "$SHIV_BIN_DIR/f")" = "foo" ]
}

@test "symlinks: shiv_remove_alias_symlinks cleans up" {
  mkdir -p "$SHIV_BIN_DIR"
  shiv_create_shim "foo" "$REPO_DIR"
  shiv_create_alias_symlinks "foo" "f"
  [ -L "$SHIV_BIN_DIR/f" ]
  shiv_remove_alias_symlinks "foo" "f"
  [ ! -L "$SHIV_BIN_DIR/f" ]
}

@test "symlinks: alias symlink is executable" {
  mkdir -p "$SHIV_BIN_DIR"
  shiv_create_shim "foo" "$REPO_DIR"
  shiv_create_alias_symlinks "foo" "f"
  [ -x "$SHIV_BIN_DIR/f" ]
}

@test "symlinks: removing shim leaves symlinks dangling" {
  mkdir -p "$SHIV_BIN_DIR"
  shiv_create_shim "foo" "$REPO_DIR"
  shiv_create_alias_symlinks "foo" "f"
  rm "$SHIV_BIN_DIR/foo"
  # Symlink still exists but target is gone
  [ -L "$SHIV_BIN_DIR/f" ]
  [ ! -e "$SHIV_BIN_DIR/f" ]
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

@test "schema: registry with package and aliases is valid" {
  if ! command -v check-jsonschema &>/dev/null; then
    skip "check-jsonschema not found"
  fi
  shiv_register "foo" "/path/to/foo" "f"
  check-jsonschema --schemafile "$REPO_DIR/registry.schema.json" "$SHIV_REGISTRY"
}

@test "schema: registry without aliases is valid" {
  if ! command -v check-jsonschema &>/dev/null; then
    skip "check-jsonschema not found"
  fi
  shiv_register "foo" "/path/to/foo"
  check-jsonschema --schemafile "$REPO_DIR/registry.schema.json" "$SHIV_REGISTRY"
}
