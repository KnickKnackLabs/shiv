#!/usr/bin/env bats
# Task --help interception
#
# mise consumes `--help` after `--` without rendering help and without binding
# arguments, so a task that declares a required arg would otherwise die on the
# unset usage_* variable before it could report anything. See lib/usage.sh.

REPO_DIR="$BATS_TEST_DIRNAME/.."

setup() {
  export TEST_HOME="$BATS_TEST_TMPDIR/shiv"
  mkdir -p "$TEST_HOME"

  # The guard exits before a task touches the registry. Point the tasks at a
  # throwaway home anyway, so a regression that lets one run cannot reach the
  # real one.
  export SHIV_BIN_DIR="$TEST_HOME/.local/bin"
  export SHIV_DATA_DIR="$TEST_HOME/.local/share/shiv"
  export SHIV_PACKAGES_DIR="$SHIV_DATA_DIR/packages"
  export SHIV_CONFIG_DIR="$TEST_HOME/.config/shiv"
  export SHIV_CACHE_DIR="$TEST_HOME/.cache/shiv"
  export SHIV_REGISTRY="$SHIV_CONFIG_DIR/registry.json"

  unset SHIV_HELP_GUARD
}

run_task() {
  mise -C "$REPO_DIR" run "$@"
}

@test "install: --help after -- renders help" {
  run run_task install -- --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: install"* ]]
  [[ "$output" != *"unbound variable"* ]]
}

@test "install: -h after -- renders help" {
  run run_task install -- -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: install"* ]]
}

@test "which: --help after -- renders help" {
  run run_task which -- --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: which"* ]]
  [[ "$output" != *"unbound variable"* ]]
}

@test "uninstall: --help after -- renders help" {
  run run_task uninstall -- --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: uninstall"* ]]
}

@test "help flag before -- still renders help" {
  run run_task install --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: install"* ]]
}

@test "missing required arg still reports a usage error" {
  run run_task which
  [ "$status" -ne 0 ]
  [[ "$output" == *"Missing required arg"* ]]
}

@test "guard does not re-enter when mise fails to render help" {
  export SHIV_HELP_GUARD=1
  run run_task which -- --help
  [ "$status" -ne 0 ]
  [[ "$output" == *"could not render help for 'which'"* ]]
}
