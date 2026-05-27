#!/usr/bin/env bats
# shiv seed test suite

REPO_DIR="$BATS_TEST_DIRNAME/.."

setup() {
  TARGET="$BATS_TEST_TMPDIR/my-tool"
  MOCK_HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$TARGET" "$MOCK_HOME"
}

# Run the seed task with TARGET as CWD
_seed() {
  run bash -c "cd '$TARGET' && MISE_CONFIG_ROOT='$REPO_DIR' bash '$REPO_DIR/.mise/tasks/seed' '$1' 2>&1"
}

# Run the generated shell task with TARGET as the repo root
_run_shell() {
  run env \
    MISE_CONFIG_ROOT="$TARGET" \
    HOME="$MOCK_HOME" \
    bash "$TARGET/.mise/tasks/shell"
}

@test "seed: creates .mise/tasks/shell in the target repo" {
  _seed "my-tool"
  [ "$status" -eq 0 ]
  [ -f "$TARGET/.mise/tasks/shell" ]
}

@test "seed: generated shell task is executable" {
  _seed "my-tool"
  [ -x "$TARGET/.mise/tasks/shell" ]
}

@test "seed: generated shell task bakes the tool name into _NAME" {
  _seed "my-tool"
  grep -q '_NAME="my-tool"' "$TARGET/.mise/tasks/shell"
}

@test "seed: generated shell task uses MISE_CONFIG_ROOT as repo path" {
  _seed "my-tool"
  grep -q '_REPO="\$MISE_CONFIG_ROOT"' "$TARGET/.mise/tasks/shell"
}

@test "seed: generated shell task creates shim at expected path" {
  _seed "my-tool"
  _run_shell
  [ -f "$MOCK_HOME/.local/bin/my-tool" ]
}

@test "seed: generated shell task makes shim executable" {
  _seed "my-tool"
  _run_shell
  [ -x "$MOCK_HOME/.local/bin/my-tool" ]
}

@test "seed: shim has repo path baked in" {
  _seed "my-tool"
  _run_shell
  grep -q "REPO=\"$TARGET\"" "$MOCK_HOME/.local/bin/my-tool"
}

@test "seed: shim delegates to mise -C REPO run" {
  _seed "my-tool"
  _run_shell
  grep -q 'exec mise -C "\$REPO" run "\$@"' "$MOCK_HOME/.local/bin/my-tool"
}

@test "seed: shim sets package-specific caller PWD var" {
  _seed "my-tool"
  _run_shell
  grep -q 'MY_TOOL_CALLER_PWD="\$PWD"' "$MOCK_HOME/.local/bin/my-tool"
}

@test "seed: generated shell task emits PATH export when bin dir is absent" {
  _seed "my-tool"
  run env \
    MISE_CONFIG_ROOT="$TARGET" \
    HOME="$MOCK_HOME" \
    PATH="/bin:/usr/bin" \
    bash "$TARGET/.mise/tasks/shell"
  [[ "$output" == *"export PATH="* ]]
  [[ "$output" == *"$MOCK_HOME/.local/bin"* ]]
}

@test "seed: generated shell task emits no PATH export when bin dir already present" {
  _seed "my-tool"
  run env \
    MISE_CONFIG_ROOT="$TARGET" \
    HOME="$MOCK_HOME" \
    PATH="$MOCK_HOME/.local/bin:/bin:/usr/bin" \
    bash "$TARGET/.mise/tasks/shell"
  [[ "$output" != *"export PATH="* ]]
}

@test "seed: errors if shell task already exists" {
  _seed "my-tool"
  _seed "my-tool"
  [ "$status" -ne 0 ]
  [[ "$output" == *"already exists"* ]]
}

@test "seed: errors when targeting shiv itself" {
  local resolved
  resolved="$(cd "$REPO_DIR" && pwd)"
  run bash -c "cd '$resolved' && MISE_CONFIG_ROOT='$resolved' bash '$REPO_DIR/.mise/tasks/seed' 'shiv' 2>&1"
  [ "$status" -ne 0 ]
  [[ "$output" == *"cannot seed into shiv itself"* ]]
}

@test "seed: caller PWD var name follows package naming convention" {
  TARGET="$BATS_TEST_TMPDIR/my-cool-pkg"
  mkdir -p "$TARGET"
  run bash -c "cd '$TARGET' && MISE_CONFIG_ROOT='$REPO_DIR' bash '$REPO_DIR/.mise/tasks/seed' 'my-cool-pkg' 2>&1"
  [ "$status" -eq 0 ]
  grep -q 'MY_COOL_PKG_CALLER_PWD' "$TARGET/.mise/tasks/shell"
}
