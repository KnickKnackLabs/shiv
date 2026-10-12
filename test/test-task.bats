#!/usr/bin/env bats
# shiv test task regression suite

REPO_DIR="$BATS_TEST_DIRNAME/.."

run_test_count() {
  cd "$REPO_DIR" && mise run -q test "$@" -c 2>"$BATS_TEST_TMPDIR/test-task-stderr"
}

@test "test task resolves bare suite names" {
  run run_test_count registry
  [ "$status" -eq 0 ]
  [ "$output" -gt 0 ]
}

@test "test task resolves named suite directories recursively" {
  local expected_count
  expected_count=$(bats --recursive --count "$REPO_DIR/test/shim")
  run run_test_count shim
  [ "$status" -eq 0 ]
  [ "$output" -eq "$expected_count" ]
}

@test "test task resolves a nested suite name" {
  run run_test_count shim/generation
  [ "$status" -eq 0 ]
  [ "$output" -eq 7 ]
}

@test "test task default discovery includes nested suites" {
  run run_test_count --filter '^shim:'
  [ "$status" -eq 0 ]
  [ "$output" -eq 40 ]
}

@test "test task does not treat directory-named filter values as targets" {
  run run_test_count --filter shim
  [ "$status" -eq 0 ]
  [ "$output" -ge 40 ]
}

@test "test task supports flag-only BATS filters" {
  run run_test_count --filter "sources: default index includes portl"
  [ "$status" -eq 0 ]
  [ "$output" -eq 1 ]
}

@test "test task does not treat filter values as suite targets" {
  run run_test_count --filter registry
  [ "$status" -eq 0 ]
  [ "$output" -gt 1 ]
}
