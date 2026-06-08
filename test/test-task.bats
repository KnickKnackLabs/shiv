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
