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
  aliases=()
  while IFS= read -r _alias; do
    [ -n "$_alias" ] && aliases+=("$_alias")
  done < <(shiv_registry_aliases "foo")
  [ "${#aliases[@]}" -eq 2 ]
  [ "${aliases[0]}" = "f" ]
  [ "${aliases[1]}" = "fo" ]
}

@test "registry: shiv_registry_aliases returns empty when none" {
  shiv_register "foo" "/path/to/foo"
  [ -z "$(shiv_registry_aliases "foo")" ]
}

@test "registry: shiv_registry_entries outputs name-tab-path-tab-ref" {
  shiv_register "alpha" "/path/a"
  SHIV_REF="v1.0" shiv_register "beta" "/path/b"
  local count=0
  shiv_registry_entries | while IFS=$'\t' read -r name path ref; do
    [ -n "$name" ] && [ -n "$path" ]
    count=$((count + 1))
  done
  [ "$(shiv_registry_entries | wc -l | tr -d ' ')" -eq 2 ]

  # Verify ref field is populated for pinned package
  local beta_ref
  beta_ref=$(shiv_registry_entries | grep '^beta' | cut -f3)
  [ "$beta_ref" = "v1.0" ]

  # Verify ref field is empty for unpinned package
  local alpha_ref
  alpha_ref=$(shiv_registry_entries | grep '^alpha' | cut -f3)
  [ -z "$alpha_ref" ]
}

@test "registry: shiv_registry_set_aliases updates aliases" {
  shiv_register "foo" "/path/to/foo" "f"
  shiv_registry_set_aliases "foo" "f" "fo" "x"
  aliases=()
  while IFS= read -r _alias; do
    [ -n "$_alias" ] && aliases+=("$_alias")
  done < <(shiv_registry_aliases "foo")
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
# Alias collision detection
# ============================================================================

@test "collision: alias that shadows a package name is rejected" {
  shiv_register "bar" "/path/to/bar"
  run shiv_register "foo" "/path/to/foo" "bar"
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "conflicts with existing package"
}

@test "collision: alias already claimed by another package is rejected" {
  shiv_register "foo" "/path/to/foo" "x"
  run shiv_register "bar" "/path/to/bar" "x"
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "already used by package"
}

@test "collision: re-registering same package with same alias succeeds" {
  shiv_register "foo" "/path/to/foo" "f"
  run shiv_register "foo" "/path/to/foo" "f"
  [ "$status" -eq 0 ]
}

@test "collision: set_aliases rejects alias shadowing a package" {
  shiv_register "foo" "/path/to/foo"
  shiv_register "bar" "/path/to/bar"
  run shiv_registry_set_aliases "foo" "bar"
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "conflicts with existing package"
}

@test "collision: set_aliases rejects alias claimed by another package" {
  shiv_register "foo" "/path/to/foo" "x"
  shiv_register "bar" "/path/to/bar"
  run shiv_registry_set_aliases "bar" "x"
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "already used by package"
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
# Ref support
# ============================================================================

@test "ref: register with ref stores ref" {
  SHIV_REF="v1.0.0" shiv_register "foo" "/path/to/foo"
  jq -e '.foo.ref == "v1.0.0"' "$SHIV_REGISTRY"
}

@test "ref: register without ref omits ref key" {
  shiv_register "foo" "/path/to/foo"
  run jq -e '.foo | has("ref")' "$SHIV_REGISTRY"
  [ "$status" -ne 0 ]
}

@test "ref: shiv_registry_ref returns ref" {
  SHIV_REF="main" shiv_register "foo" "/path/to/foo"
  [ "$(shiv_registry_ref "foo")" = "main" ]
}

@test "ref: shiv_registry_ref returns empty for unpinned" {
  shiv_register "foo" "/path/to/foo"
  [ -z "$(shiv_registry_ref "foo")" ]
}

@test "ref: register with ref and aliases stores both" {
  SHIV_REF="v2.0" shiv_register "foo" "/path/to/foo" "f"
  jq -e '.foo.ref == "v2.0"' "$SHIV_REGISTRY"
  jq -e '.foo.aliases == ["f"]' "$SHIV_REGISTRY"
}

@test "ref: re-register without ref clears previous ref" {
  SHIV_REF="v1.0" shiv_register "foo" "/path/to/foo"
  shiv_register "foo" "/path/to/foo"
  run jq -e '.foo | has("ref")' "$SHIV_REGISTRY"
  [ "$status" -ne 0 ]
}

# ============================================================================
# Ref type detection
# ============================================================================

@test "ref-type: detects short commit SHA" {
  result=$(shiv_detect_ref_type "any/repo" "abc1234")
  [ "$result" = "commit" ]
}

@test "ref-type: detects full 40-char commit SHA" {
  result=$(shiv_detect_ref_type "any/repo" "abcdef1234abcdef1234abcdef1234abcdef1234")
  [ "$result" = "commit" ]
}

@test "ref-type: rejects uppercase hex as commit SHA" {
  # Uppercase is not a valid SHA — falls through to ls-remote
  run shiv_detect_ref_type "nonexistent/repo" "ABC1234"
  [ "$status" -ne 0 ]
}

@test "ref-type: rejects too-short hex as commit SHA" {
  # 6 chars is below the 7-char minimum
  run shiv_detect_ref_type "nonexistent/repo" "abc123"
  [ "$status" -ne 0 ]
}

@test "ref-type: non-hex string is not a commit SHA" {
  # "foobar7" contains non-hex chars, should not match SHA pattern
  run shiv_detect_ref_type "nonexistent/repo" "foobar7"
  [ "$status" -ne 0 ]
}

@test "ref-type: ls-remote failure with non-SHA ref shows error" {
  # A non-SHA ref against a nonexistent repo should surface the network error
  run shiv_detect_ref_type "nonexistent/repo" "some-branch"
  [ "$status" -ne 0 ]
  [[ "$output" == *"failed to query refs"* ]]
}

@test "ref-type: ls-remote failure with SHA ref falls through to commit" {
  # A SHA pattern against a nonexistent repo should still return "commit"
  # (ls-remote fails but the ref looks like a SHA, so we assume commit)
  result=$(shiv_detect_ref_type "nonexistent/repo" "abc1234")
  [ "$result" = "commit" ]
}

# ============================================================================
# Schema validation
# ============================================================================

@test "schema: empty registry is valid" {
  if ! command -v jsonschema &>/dev/null; then
    skip "jsonschema not found"
  fi
  jsonschema validate "$REPO_DIR/registry.schema.json" "$SHIV_REGISTRY"
}

@test "schema: registry with package and aliases is valid" {
  if ! command -v jsonschema &>/dev/null; then
    skip "jsonschema not found"
  fi
  shiv_register "foo" "/path/to/foo" "f"
  jsonschema validate "$REPO_DIR/registry.schema.json" "$SHIV_REGISTRY"
}

@test "schema: registry without aliases is valid" {
  if ! command -v jsonschema &>/dev/null; then
    skip "jsonschema not found"
  fi
  shiv_register "foo" "/path/to/foo"
  jsonschema validate "$REPO_DIR/registry.schema.json" "$SHIV_REGISTRY"
}

@test "schema: registry with ref is valid" {
  if ! command -v jsonschema &>/dev/null; then
    skip "jsonschema not found"
  fi
  SHIV_REF="v1.0.0" shiv_register "foo" "/path/to/foo"
  jsonschema validate "$REPO_DIR/registry.schema.json" "$SHIV_REGISTRY"
}

@test "schema: registry with ref and aliases is valid" {
  if ! command -v jsonschema &>/dev/null; then
    skip "jsonschema not found"
  fi
  SHIV_REF="v1.0.0" shiv_register "foo" "/path/to/foo" "f"
  jsonschema validate "$REPO_DIR/registry.schema.json" "$SHIV_REGISTRY"
}
