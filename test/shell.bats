#!/usr/bin/env bats
# shiv shell task tests — PATH setup for shiv + mise shims
#
# Tests the PATH-emitting logic from the shell task directly,
# without running through `mise run` (which requires trust/install
# of the full global config and is slow in test).

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

# Helper: run just the PATH-emitting logic from the shell task.
# This avoids needing mise trust/install for the global config.
run_shell_path_logic() {
  bash -c '
    source "'"$REPO_DIR"'/lib/shim.sh"

    # Ensure ~/.local/bin is on PATH (skip if already there)
    case ":$PATH:" in
      *":$SHIV_BIN_DIR:"*) ;;
      *) echo "export PATH=\"$SHIV_BIN_DIR:\$PATH\"" ;;
    esac

    # Ensure mise shims are on PATH
    MISE_SHIMS_DIR="${MISE_DATA_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/mise}/shims"
    if [ -d "$MISE_SHIMS_DIR" ]; then
      case ":$PATH:" in
        *":$MISE_SHIMS_DIR:"*) ;;
        *) echo "export PATH=\"$MISE_SHIMS_DIR:\$PATH\"" ;;
      esac
    fi
  '
}

# ============================================================================
# SHIV_BIN_DIR on PATH
# ============================================================================

@test "shell: adds SHIV_BIN_DIR to PATH when not present" {
  export PATH="${PATH//$SHIV_BIN_DIR:/}"

  run run_shell_path_logic
  [ "$status" -eq 0 ]
  [[ "$output" == *"export PATH=\"$SHIV_BIN_DIR:"* ]]
}

@test "shell: skips SHIV_BIN_DIR when already on PATH" {
  export PATH="$SHIV_BIN_DIR:$PATH"

  run run_shell_path_logic
  [ "$status" -eq 0 ]
  [[ "$output" != *"export PATH=\"$SHIV_BIN_DIR:"* ]]
}

# ============================================================================
# Mise shims on PATH
# ============================================================================

@test "shell: adds mise shims dir to PATH when present on disk" {
  local shims_dir="$TEST_HOME/.local/share/mise/shims"
  mkdir -p "$shims_dir"
  export PATH="${PATH//$shims_dir:/}"

  run run_shell_path_logic
  [ "$status" -eq 0 ]
  [[ "$output" == *"export PATH=\"$shims_dir:"* ]]
}

@test "shell: skips mise shims dir when already on PATH" {
  local shims_dir="$TEST_HOME/.local/share/mise/shims"
  mkdir -p "$shims_dir"
  export PATH="$shims_dir:$PATH"

  run run_shell_path_logic
  [ "$status" -eq 0 ]
  [[ "$output" != *"export PATH=\"$shims_dir:"* ]]
}

@test "shell: skips mise shims dir when it does not exist" {
  run run_shell_path_logic
  [ "$status" -eq 0 ]
  [[ "$output" != *"mise/shims"* ]]
}

@test "shell: mise shims emitted after SHIV_BIN_DIR (ends up first on PATH)" {
  local shims_dir="$TEST_HOME/.local/share/mise/shims"
  mkdir -p "$shims_dir"
  export PATH="${PATH//$SHIV_BIN_DIR:/}"
  export PATH="${PATH//$shims_dir:/}"

  run run_shell_path_logic
  [ "$status" -eq 0 ]

  # Both should be present
  [[ "$output" == *"$SHIV_BIN_DIR"* ]]
  [[ "$output" == *"$shims_dir"* ]]

  # SHIV_BIN_DIR should appear before mise shims in output
  # (since both prepend, the later one ends up first on PATH)
  local bin_line shims_line
  bin_line=$(echo "$output" | grep -n "$SHIV_BIN_DIR" | head -1 | cut -d: -f1)
  shims_line=$(echo "$output" | grep -n "mise/shims" | head -1 | cut -d: -f1)
  [ "$bin_line" -lt "$shims_line" ]
}

@test "shell: respects MISE_DATA_DIR for shims path" {
  local custom_mise="$TEST_HOME/custom-mise"
  local shims_dir="$custom_mise/shims"
  mkdir -p "$shims_dir"
  export MISE_DATA_DIR="$custom_mise"

  run run_shell_path_logic
  [ "$status" -eq 0 ]
  [[ "$output" == *"export PATH=\"$shims_dir:"* ]]
}

@test "shell: respects XDG_DATA_HOME for shims path" {
  local xdg_data="$TEST_HOME/xdg-data"
  local shims_dir="$xdg_data/mise/shims"
  mkdir -p "$shims_dir"
  export XDG_DATA_HOME="$xdg_data"
  unset MISE_DATA_DIR

  run run_shell_path_logic
  [ "$status" -eq 0 ]
  [[ "$output" == *"export PATH=\"$shims_dir:"* ]]
}

# ============================================================================
# End-to-end: eval output produces correct PATH ordering
# ============================================================================

@test "shell: eval output puts mise shims before SHIV_BIN_DIR on PATH" {
  local shims_dir="$TEST_HOME/.local/share/mise/shims"
  mkdir -p "$shims_dir"
  export PATH="${PATH//$SHIV_BIN_DIR:/}"
  export PATH="${PATH//$shims_dir:/}"

  # Eval the output and check resulting PATH
  eval "$(run_shell_path_logic)"

  # mise shims should come before SHIV_BIN_DIR
  local shims_pos bin_pos
  shims_pos=$(echo "$PATH" | tr ':' '\n' | grep -n "mise/shims" | head -1 | cut -d: -f1)
  bin_pos=$(echo "$PATH" | tr ':' '\n' | grep -n "$SHIV_BIN_DIR" | head -1 | cut -d: -f1)
  [ "$shims_pos" -lt "$bin_pos" ]
}
