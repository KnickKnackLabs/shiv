# Shared test helpers for shiv BATS test suite

# Put a mock `shiv` on PATH that delegates to mise.
# This lets tests exercise the full shim → mise → task chain
# without depending on the real shiv shim being installed.
setup_shiv_on_path() {
  local mock_bin="$BATS_TEST_TMPDIR/mock-bin"
  mkdir -p "$mock_bin"
  cat > "$mock_bin/shiv" <<MOCK
#!/usr/bin/env bash
export CALLER_PWD="\$PWD"
exec mise -C "$REPO_DIR" run -q "\$@"
MOCK
  chmod +x "$mock_bin/shiv"
  export PATH="$mock_bin:$PATH"
}
