# Shared test helpers for shiv BATS test suite

# Put a mock `shiv` on PATH that delegates to mise.
# This lets tests exercise the full shim → mise → task chain
# without depending on the real shiv shim being installed.
setup_shiv_on_path() {
  local mock_bin="$BATS_TEST_TMPDIR/mock-bin"
  mkdir -p "$mock_bin"
  cat > "$mock_bin/shiv" <<MOCK
#!/usr/bin/env bash
export SHIV_CALLER_PWD="\$PWD"
exec mise -C "$REPO_DIR" run -q "\$@"
MOCK
  chmod +x "$mock_bin/shiv"
  export PATH="$mock_bin:$PATH"
}

# Preserve command data while avoiding repeated terminal rendering in tests
# whose claim is package behavior rather than Gum integration.
mock_gum_formatting() {
  local mock_gum="$BATS_TEST_TMPDIR/mock-bin/gum"
  cat > "$mock_gum" <<'MOCK'
#!/usr/bin/env bash
command="${1:-}"
if [ "$#" -gt 0 ]; then
  shift
fi
case "$command" in
  style)
    while [[ "${1:-}" == --* ]]; do shift; done
    printf '%s\n' "$*"
    ;;
  table)
    cat
    ;;
  *)
    printf 'unexpected mocked gum command: %s\n' "$command" >&2
    exit 2
    ;;
esac
MOCK
  chmod +x "$mock_gum"
}

use_real_gum() {
  rm -f "$BATS_TEST_TMPDIR/mock-bin/gum"
}
