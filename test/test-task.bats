#!/usr/bin/env bats
# shiv test task regression suite

load helpers

REPO_DIR="$BATS_TEST_DIRNAME/.."

setup() {
  setup_shiv_on_path
}

run_test_count() {
  shiv test "$@" -c 2>"$BATS_TEST_TMPDIR/test-task-stderr"
}

shiv_test_isolated() {
  env -i \
    HOME="$HOME" \
    PATH="$PATH" \
    TMPDIR="${TMPDIR:-/tmp}" \
    MISE_TRUSTED_CONFIG_PATHS="$REPO_DIR" \
    PROBE_DIR="${PROBE_DIR:-}" \
    shiv test "$@"
}

@test "public test task owns the complete BATS runner" {
  run grep -n '^    exec bats ' "$REPO_DIR/.mise/tasks/test"
  [ "$status" -eq 0 ]
  [ ! -e "$REPO_DIR/libexec/test" ]
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

@test "public task runs separate BATS files concurrently" {
  probe_dir="$BATS_TEST_TMPDIR/cross-file-probe"
  barrier_dir="$BATS_TEST_TMPDIR/cross-file-barrier"
  mkdir -p "$probe_dir" "$barrier_dir"

  test_keyword='@test'
  {
    printf '%s\n' '#!/usr/bin/env bats'
    printf '%s\n' "$test_keyword \"first worker observes second worker\" {"
    cat <<'BATS'
  touch "$PROBE_DIR/one"
  for _ in {1..50}; do
    [ ! -e "$PROBE_DIR/two" ] || return 0
    sleep 0.05
  done
  false
}
BATS
  } > "$probe_dir/one.bats"

  {
    printf '%s\n' '#!/usr/bin/env bats'
    printf '%s\n' "$test_keyword \"second worker observes first worker\" {"
    cat <<'BATS'
  touch "$PROBE_DIR/two"
  for _ in {1..50}; do
    [ ! -e "$PROBE_DIR/one" ] || return 0
    sleep 0.05
  done
  false
}
BATS
  } > "$probe_dir/two.bats"

  export PROBE_DIR="$barrier_dir"
  run shiv_test_isolated "$probe_dir"
  [ "$status" -eq 0 ]
  [[ "$output" == *"jobs across and within isolated suites"* ]]
}

@test "public task runs tests within one BATS file concurrently" {
  probe_dir="$BATS_TEST_TMPDIR/within-file-probe"
  barrier_dir="$BATS_TEST_TMPDIR/within-file-barrier"
  mkdir -p "$probe_dir" "$barrier_dir"

  test_keyword='@test'
  {
    printf '%s\n' '#!/usr/bin/env bats'
    printf '%s\n' "$test_keyword \"first test observes second test\" {"
    cat <<'BATS'
  touch "$PROBE_DIR/one"
  for _ in {1..50}; do
    [ ! -e "$PROBE_DIR/two" ] || return 0
    sleep 0.05
  done
  false
}
BATS
    printf '%s\n' "$test_keyword \"second test observes first test\" {"
    cat <<'BATS'
  touch "$PROBE_DIR/two"
  for _ in {1..50}; do
    [ ! -e "$PROBE_DIR/one" ] || return 0
    sleep 0.05
  done
  false
}
BATS
  } > "$probe_dir/within-file.bats"

  export PROBE_DIR="$barrier_dir"
  run shiv_test_isolated "$probe_dir"
  [ "$status" -eq 0 ]
  [[ "$output" == *"jobs across and within isolated suites"* ]]
}
