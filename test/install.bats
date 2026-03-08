#!/usr/bin/env bats
# shiv install test suite

REPO_DIR="$BATS_TEST_DIRNAME/.."

setup() {
  source "$REPO_DIR/lib/shim.sh"

  # Use a temporary home for isolation
  export TEST_HOME="$BATS_TMPDIR/shiv-test-$$"
  mkdir -p "$TEST_HOME"

  # Override shiv paths to use test home
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
# Basic install (local path)
# ============================================================================

@test "install: local path creates shim with package name" {
  run mise -C "$REPO_DIR" run -q install shiv "$REPO_DIR"
  [ "$status" -eq 0 ]
  [ -f "$SHIV_BIN_DIR/shiv" ]
  # Registry should have the entry
  jq -e '.shiv' "$SHIV_REGISTRY"
}

# ============================================================================
# Custom command name (--as)
# ============================================================================

@test "install --as: creates shim with custom name" {
  run mise -C "$REPO_DIR" run -q install shiv "$REPO_DIR" --as sv
  [ "$status" -eq 0 ]
  [ -f "$SHIV_BIN_DIR/sv" ]
  # Should NOT create a shim with the package name
  [ ! -f "$SHIV_BIN_DIR/shiv" ]
}

@test "install --as: registers under custom name" {
  mise -C "$REPO_DIR" run -q install shiv "$REPO_DIR" --as sv
  # Registry key should be the custom name
  jq -e '.sv' "$SHIV_REGISTRY"
  # Package name should not be in registry
  run jq -e '.shiv' "$SHIV_REGISTRY"
  [ "$status" -ne 0 ]
}

@test "install --as: caches under custom name" {
  mise -C "$REPO_DIR" run -q install shiv "$REPO_DIR" --as sv
  [ -f "$SHIV_CACHE_DIR/completions/sv.cache" ]
  [ ! -f "$SHIV_CACHE_DIR/completions/shiv.cache" ]
}

@test "install --as: shim points to correct repo" {
  mise -C "$REPO_DIR" run -q install shiv "$REPO_DIR" --as sv
  # Shim should contain the repo path (resolved to absolute)
  grep -q "# managed by shiv" "$SHIV_BIN_DIR/sv"
  grep -q "REPO=" "$SHIV_BIN_DIR/sv"
}

@test "install --as: output shows alias" {
  run mise -C "$REPO_DIR" run -q install shiv "$REPO_DIR" --as sv
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Alias: shiv → sv"
}

@test "install --as: completions use custom name" {
  mise -C "$REPO_DIR" run -q install shiv "$REPO_DIR" --as sv
  run mise -C "$REPO_DIR" run -q completions:bash
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "complete -F _shiv_complete_sv sv"
}

# ============================================================================
# Default behavior (no --as)
# ============================================================================

@test "install: without --as uses package name as command" {
  run mise -C "$REPO_DIR" run -q install shiv "$REPO_DIR"
  [ "$status" -eq 0 ]
  [ -f "$SHIV_BIN_DIR/shiv" ]
  jq -e '.shiv' "$SHIV_REGISTRY"
  # No alias line in output
  echo "$output" | grep -qv "Alias:" || true
}
