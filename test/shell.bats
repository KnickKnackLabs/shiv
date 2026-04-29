#!/usr/bin/env bats
# shiv shell task tests — PATH setup for shiv + mise shims

REPO_DIR="$BATS_TEST_DIRNAME/.."
load helpers

setup() {
  source "$REPO_DIR/lib/shim.sh"

  export TEST_HOME="$BATS_TMPDIR/shiv-test-$$"
  mkdir -p "$TEST_HOME"

  export HOME="$TEST_HOME"
  export SHIV_BIN_DIR="$TEST_HOME/.local/bin"
  export SHIV_DATA_DIR="$TEST_HOME/.local/share/shiv"
  export SHIV_PACKAGES_DIR="$SHIV_DATA_DIR/packages"
  export SHIV_CONFIG_DIR="$TEST_HOME/.config/shiv"
  export SHIV_CACHE_DIR="$TEST_HOME/.cache/shiv"
  export SHIV_REGISTRY="$SHIV_CONFIG_DIR/registry.json"

  mkdir -p "$SHIV_BIN_DIR"
  shiv_init_registry
}

teardown() {
  rm -rf "$TEST_HOME"
}

# ============================================================================
# SHIV_BIN_DIR on PATH
# ============================================================================

@test "shell: adds SHIV_BIN_DIR to PATH when not present" {
  export PATH="${PATH//$SHIV_BIN_DIR:/}"

  run shiv_emit_path_exports
  [ "$status" -eq 0 ]
  [[ "$output" == *"export PATH='$SHIV_BIN_DIR:"* ]]
}

@test "shell: skips SHIV_BIN_DIR when already first on PATH" {
  export PATH="$SHIV_BIN_DIR:$PATH"

  run shiv_emit_path_exports
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ============================================================================
# Mise shims on PATH
# ============================================================================

@test "shell: adds mise shims dir before SHIV_BIN_DIR when present on disk" {
  local shims_dir="$TEST_HOME/.local/share/mise/shims"
  mkdir -p "$shims_dir"
  export PATH="${PATH//$SHIV_BIN_DIR:/}"
  export PATH="${PATH//$shims_dir:/}"

  run shiv_emit_path_exports
  [ "$status" -eq 0 ]
  [[ "$output" == *"export PATH='$shims_dir:$SHIV_BIN_DIR:"* ]]
}

@test "shell: skips output when mise shims and SHIV_BIN_DIR are already ordered" {
  local shims_dir="$TEST_HOME/.local/share/mise/shims"
  mkdir -p "$shims_dir"
  export PATH="$shims_dir:$SHIV_BIN_DIR:$PATH"

  run shiv_emit_path_exports
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "shell: skips mise shims dir when it does not exist" {
  local shims_dir="$TEST_HOME/.local/share/mise/shims"

  run shiv_emit_path_exports
  [ "$status" -eq 0 ]
  [[ "$output" != *"$shims_dir"* ]]
}

@test "shell: corrects wrong-order PATH so mise shims precede SHIV_BIN_DIR" {
  local shims_dir="$TEST_HOME/.local/share/mise/shims"
  mkdir -p "$shims_dir"
  export PATH="$SHIV_BIN_DIR:$shims_dir:$PATH"

  run shiv_emit_path_exports
  [ "$status" -eq 0 ]
  [[ "$output" == *"export PATH='$shims_dir:$SHIV_BIN_DIR:"* ]]
}

@test "shell: respects MISE_DATA_DIR for shims path" {
  local custom_mise="$TEST_HOME/custom-mise"
  local shims_dir="$custom_mise/shims"
  mkdir -p "$shims_dir"
  export MISE_DATA_DIR="$custom_mise"

  run shiv_emit_path_exports
  [ "$status" -eq 0 ]
  [[ "$output" == *"export PATH='$shims_dir:$SHIV_BIN_DIR:"* ]]
}

@test "shell: respects XDG_DATA_HOME for shims path" {
  local xdg_data="$TEST_HOME/xdg-data"
  local shims_dir="$xdg_data/mise/shims"
  mkdir -p "$shims_dir"
  export XDG_DATA_HOME="$xdg_data"
  unset MISE_DATA_DIR

  run shiv_emit_path_exports
  [ "$status" -eq 0 ]
  [[ "$output" == *"export PATH='$shims_dir:$SHIV_BIN_DIR:"* ]]
}

# ============================================================================
# End-to-end: eval output produces correct PATH ordering
# ============================================================================

@test "shell: eval output puts mise shims before SHIV_BIN_DIR on PATH" {
  local shims_dir="$TEST_HOME/.local/share/mise/shims"
  mkdir -p "$shims_dir"
  export PATH="${PATH//$SHIV_BIN_DIR:/}"
  export PATH="${PATH//$shims_dir:/}"

  eval "$(shiv_emit_path_exports)"

  # mise shims should come before SHIV_BIN_DIR
  local shims_pos bin_pos
  shims_pos=$(echo "$PATH" | tr ':' '\n' | grep -nF "$shims_dir" | head -1 | cut -d: -f1)
  bin_pos=$(echo "$PATH" | tr ':' '\n' | grep -nF "$SHIV_BIN_DIR" | head -1 | cut -d: -f1)
  [ "$shims_pos" -lt "$bin_pos" ]
}

@test "shell: eval output corrects existing wrong-order PATH" {
  local shims_dir="$TEST_HOME/.local/share/mise/shims"
  mkdir -p "$shims_dir"
  export PATH="$SHIV_BIN_DIR:$shims_dir:$PATH"

  eval "$(shiv_emit_path_exports)"

  local shims_pos bin_pos
  shims_pos=$(echo "$PATH" | tr ':' '\n' | grep -nF "$shims_dir" | head -1 | cut -d: -f1)
  bin_pos=$(echo "$PATH" | tr ':' '\n' | grep -nF "$SHIV_BIN_DIR" | head -1 | cut -d: -f1)
  [ "$shims_pos" -lt "$bin_pos" ]
}

@test "shell: eval output de-duplicates managed PATH entries" {
  local shims_dir="$TEST_HOME/.local/share/mise/shims"
  mkdir -p "$shims_dir"
  export PATH="$SHIV_BIN_DIR:$shims_dir:$SHIV_BIN_DIR:$PATH:$shims_dir"

  eval "$(shiv_emit_path_exports)"

  local shims_count bin_count
  shims_count=$(echo "$PATH" | tr ':' '\n' | grep -cF "$shims_dir")
  bin_count=$(echo "$PATH" | tr ':' '\n' | grep -cF "$SHIV_BIN_DIR")
  [ "$shims_count" -eq 1 ]
  [ "$bin_count" -eq 1 ]
}
