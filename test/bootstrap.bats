#!/usr/bin/env bats
# bin/shiv bootstrap wrapper tests

REPO_DIR="$BATS_TEST_DIRNAME/.."

setup() {
  MOCK_BIN="$BATS_TEST_TMPDIR/mock-bin"
  mkdir -p "$MOCK_BIN"
}

# Fake mise: records every invocation to mise-calls, exits 0.
_mock_mise() {
  cat > "$MOCK_BIN/mise" <<MOCK
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$BATS_TEST_TMPDIR/mise-calls"
MOCK
  chmod +x "$MOCK_BIN/mise"
}

# A PATH containing only dirname — no mise, no curl.
_minimal_path() {
  local mini="$BATS_TEST_TMPDIR/mini-bin"
  mkdir -p "$mini"
  ln -sf "$(command -v dirname)" "$mini/dirname"
  echo "$mini"
}

@test "bin/shiv: delegates to mise -C <repo-root> run <args> when mise is present" {
  _mock_mise
  local expected
  expected="$(cd "$REPO_DIR" && pwd)"
  run env PATH="$MOCK_BIN:$PATH" bash "$REPO_DIR/bin/shiv" install foo --flag
  [ "$status" -eq 0 ]
  grep -qF -- "-C $expected run install foo --flag" "$BATS_TEST_TMPDIR/mise-calls"
}

@test "bin/shiv: resolves repo root from BASH_SOURCE not from caller CWD" {
  _mock_mise
  local expected
  expected="$(cd "$REPO_DIR" && pwd)"
  run bash -c "cd '$BATS_TEST_TMPDIR' && PATH='$MOCK_BIN:$PATH' bash '$REPO_DIR/bin/shiv' sometask"
  [ "$status" -eq 0 ]
  grep -qF -- "-C $expected run sometask" "$BATS_TEST_TMPDIR/mise-calls"
}

@test "bin/shiv: exits 1 with curl-required message when mise and curl are both absent" {
  local mini bash_bin
  mini="$(_minimal_path)"
  bash_bin="$(command -v bash)"
  run bash -c "PATH='$mini' '$bash_bin' '$REPO_DIR/bin/shiv' sometask 2>&1"
  [ "$status" -eq 1 ]
  [[ "$output" == *"curl required"* ]]
}
