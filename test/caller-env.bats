#!/usr/bin/env bats
# Generated-shim boundary tests with fictional settings and a fake Mise edge.

REPO_DIR="$BATS_TEST_DIRNAME/.."
load helpers

setup() {
  cd "$BATS_TEST_TMPDIR"
  source "$REPO_DIR/lib/shim.sh"
  export SHIV_BIN_DIR="$BATS_TEST_TMPDIR/bin"
  export SHIV_CACHE_DIR="$BATS_TEST_TMPDIR/cache"
  export TEST_PACKAGE="$BATS_TEST_TMPDIR/package with spaces"
  mkdir -p "$SHIV_BIN_DIR" "$TEST_PACKAGE/.mise/tasks" "$SHIV_CACHE_DIR/tasks"
  touch "$TEST_PACKAGE/.mise/tasks/_default"

  # Capture the environment at the package-Mise boundary. This fake edge does
  # not prove actual Mise restoration; env-restore.bats covers that separately.
  cat > "$SHIV_BIN_DIR/mise" <<'SH'
#!/usr/bin/env bash
exec bash "$TEST_PACKAGE/check.sh"
SH
  chmod +x "$SHIV_BIN_DIR/mise"
  export PATH="$SHIV_BIN_DIR:$PATH"
}

run_shim() {
  shiv_create_shim "$1" "$TEST_PACKAGE"
  run "$SHIV_BIN_DIR/$1"
  [ "$status" -eq 0 ]
}

@test "caller env: generated shim preserves exported empty and multiline values exactly" {
  export MYAPP_EMPTY=''
  export SHIV_CALLER_VALUE_6d79617070_MYAPP_EMPTY='stale value'
  export MYAPP_TEXT=$'a spaced value\n$(touch should-not-exist) "quotes" \\ tail\n'
  export EXPECTED_TEXT="$MYAPP_TEXT"
  MYAPP_LOCAL_ONLY='not exported'
  cat > "$TEST_PACKAGE/check.sh" <<'SH'
set -eu
[ "${SHIV_CALLER_VALUE_6d79617070_MYAPP_EMPTY+x}" = x ]
[ "$SHIV_CALLER_VALUE_6d79617070_MYAPP_EMPTY" = '' ]
[ "$SHIV_CALLER_VALUE_6d79617070_MYAPP_TEXT" = "$EXPECTED_TEXT" ]
[ "${SHIV_CALLER_VALUE_6d79617070_MYAPP_LOCAL_ONLY+x}" != x ]
[ ! -e should-not-exist ]
SH
  run_shim myapp
}

@test "caller env: absent settings clear stale same-owner snapshots only" {
  unset MYAPP_PROVIDER
  export SHIV_CALLER_VALUE_6d79617070_MYAPP_PROVIDER='stale'
  export SHIV_CALLER_VALUE_6f74686572_OTHER_PROVIDER='other caller'
  export OTHER_PROVIDER='unrelated'
  cat > "$TEST_PACKAGE/check.sh" <<'SH'
set -eu
[ "${SHIV_CALLER_VALUE_6d79617070_MYAPP_PROVIDER+x}" != x ]
[ "$SHIV_CALLER_VALUE_6f74686572_OTHER_PROVIDER" = 'other caller' ]
[ "${SHIV_CALLER_VALUE_6f74686572_OTHER_PROVIDER_EXTRA+x}" != x ]
SH
  run_shim myapp
}

@test "caller env: sanitized namespaces keep caller cwd fresh and outside snapshots" {
  export MY_TOOL_PROVIDER='fictional'
  export MY_TOOL_CALLER_PWD='/stale'
  export SHIV_CALLER_VALUE_6d792d746f6f6c_MY_TOOL_CALLER_PWD='/stale snapshot'
  export EXPECTED_CWD="$PWD"
  cat > "$TEST_PACKAGE/check.sh" <<'SH'
set -eu
[ "$SHIV_CALLER_VALUE_6d792d746f6f6c_MY_TOOL_PROVIDER" = fictional ]
[ "$MY_TOOL_CALLER_PWD" = "$EXPECTED_CWD" ]
[ "${SHIV_CALLER_VALUE_6d792d746f6f6c_MY_TOOL_CALLER_PWD+x}" != x ]
SH
  run_shim my-tool
}

@test "caller env: Shiv namespace does not snapshot reserved handoff variables" {
  export SHIV_EXAMPLE='fictional'
  export SHIV_CALLER_VALUE_6f74686572_OTHER_EXAMPLE='outer package'
  cat > "$TEST_PACKAGE/check.sh" <<'SH'
set -eu
[ "$SHIV_CALLER_VALUE_73686976_SHIV_EXAMPLE" = fictional ]
[ "$SHIV_CALLER_VALUE_6f74686572_OTHER_EXAMPLE" = 'outer package' ]
[ "${SHIV_CALLER_VALUE_73686976_SHIV_CALLER_VALUE_6f74686572_OTHER_EXAMPLE+x}" != x ]
SH
  run_shim shiv
}

@test "caller env: shorter package prefix cannot clear or replace an outer snapshot" {
  export MY_TOOL_PROVIDER='original outer caller'
  shiv_create_shim my "$TEST_PACKAGE"
  export INNER_SHIM="$SHIV_BIN_DIR/my"
  cat > "$TEST_PACKAGE/check.sh" <<'SH'
set -eu
if [ "${INNER_CALL:-}" = true ]; then
  [ "$SHIV_CALLER_VALUE_6d792d746f6f6c_MY_TOOL_PROVIDER" = 'original outer caller' ]
else
  export INNER_CALL=true
  unset MY_TOOL_PROVIDER
  "$INNER_SHIM"
  export MY_TOOL_PROVIDER='package default'
  "$INNER_SHIM"
fi
SH
  run_shim my-tool
}

@test "caller env: package names that sanitize identically keep distinct snapshots" {
  export MY_TOOL_PROVIDER='underscore caller'
  export SHIV_CALLER_VALUE_6d792d746f6f6c_MY_TOOL_PROVIDER='hyphen caller'
  cat > "$TEST_PACKAGE/check.sh" <<'SH'
set -eu
[ "$SHIV_CALLER_VALUE_6d792d746f6f6c_MY_TOOL_PROVIDER" = 'hyphen caller' ]
[ "$SHIV_CALLER_VALUE_6d795f746f6f6c_MY_TOOL_PROVIDER" = 'underscore caller' ]
SH
  run_shim my_tool
}
