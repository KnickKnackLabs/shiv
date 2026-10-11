#!/usr/bin/env bats
# Generated-shim boundary tests with fictional settings and a fake Mise edge.

REPO_DIR="$BATS_TEST_DIRNAME/.."
load helpers

setup() {
  source "$REPO_DIR/lib/shim.sh"
  export SHIV_BIN_DIR="$BATS_TEST_TMPDIR/bin"
  export SHIV_CACHE_DIR="$BATS_TEST_TMPDIR/cache"
  export TEST_PACKAGE="$BATS_TEST_TMPDIR/package with spaces"
  mkdir -p "$SHIV_BIN_DIR" "$TEST_PACKAGE/.mise/tasks" "$SHIV_CACHE_DIR/tasks"
  touch "$TEST_PACKAGE/.mise/tasks/_default"

  # Capture the environment at the package-Mise boundary, without installing
  # anything or pretending this fake edge proves actual Mise restoration.
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
  export SHIV_CALLER_MYAPP_EMPTY='stale value'
  export MYAPP_TEXT=$'a spaced value\n$(touch should-not-exist) "quotes" \\ tail\n'
  export EXPECTED_TEXT="$MYAPP_TEXT"
  MYAPP_LOCAL_ONLY='not exported'
  cat > "$TEST_PACKAGE/check.sh" <<'SH'
set -eu
[ "${SHIV_CALLER_MYAPP_EMPTY+x}" = x ]
[ "$SHIV_CALLER_MYAPP_EMPTY" = '' ]
[ "$SHIV_CALLER_MYAPP_TEXT" = "$EXPECTED_TEXT" ]
[ "${SHIV_CALLER_MYAPP_LOCAL_ONLY+x}" != x ]
[ ! -e should-not-exist ]
SH
  run_shim myapp
}

@test "caller env: absent settings clear stale same-package snapshots only" {
  unset MYAPP_PROVIDER
  export SHIV_CALLER_MYAPP_PROVIDER='stale'
  export SHIV_CALLER_OTHER_PROVIDER='other caller'
  export OTHER_PROVIDER='unrelated'
  cat > "$TEST_PACKAGE/check.sh" <<'SH'
set -eu
[ "${SHIV_CALLER_MYAPP_PROVIDER+x}" != x ]
[ "$SHIV_CALLER_OTHER_PROVIDER" = 'other caller' ]
[ "${SHIV_CALLER_OTHER_PROVIDER_EXTRA+x}" != x ]
SH
  run_shim myapp
}

@test "caller env: sanitized namespaces keep caller cwd fresh and outside snapshots" {
  export MY_TOOL_PROVIDER='fictional'
  export MY_TOOL_CALLER_PWD='/stale'
  export SHIV_CALLER_MY_TOOL_CALLER_PWD='/stale snapshot'
  export EXPECTED_CWD="$PWD"
  cat > "$TEST_PACKAGE/check.sh" <<'SH'
set -eu
[ "$SHIV_CALLER_MY_TOOL_PROVIDER" = fictional ]
[ "$MY_TOOL_CALLER_PWD" = "$EXPECTED_CWD" ]
[ "${SHIV_CALLER_MY_TOOL_CALLER_PWD+x}" != x ]
SH
  run_shim my-tool
}

@test "caller env: Shiv namespace does not snapshot reserved handoff variables" {
  export SHIV_EXAMPLE='fictional'
  export SHIV_CALLER_OTHER_EXAMPLE='outer package'
  cat > "$TEST_PACKAGE/check.sh" <<'SH'
set -eu
[ "$SHIV_CALLER_SHIV_EXAMPLE" = fictional ]
[ "$SHIV_CALLER_OTHER_EXAMPLE" = 'outer package' ]
[ "${SHIV_CALLER_SHIV_CALLER_OTHER_EXAMPLE+x}" != x ]
SH
  run_shim shiv
}
