#!/usr/bin/env bats
# shiv which test suite

REPO_DIR="$BATS_TEST_DIRNAME/.."
load helpers

setup() {
  source "$REPO_DIR/lib/shim.sh"

  export TEST_HOME="$BATS_TMPDIR/shiv-test-$$"
  mkdir -p "$TEST_HOME"

  export SHIV_BIN_DIR="$TEST_HOME/.local/bin"
  export SHIV_DATA_DIR="$TEST_HOME/.local/share/shiv"
  export SHIV_PACKAGES_DIR="$SHIV_DATA_DIR/packages"
  export SHIV_CONFIG_DIR="$TEST_HOME/.config/shiv"
  export SHIV_CACHE_DIR="$TEST_HOME/.cache/shiv"
  export SHIV_REGISTRY="$SHIV_CONFIG_DIR/registry.json"

  mkdir -p "$SHIV_BIN_DIR"
  shiv_init_registry
  setup_shiv_on_path

  export MISE_BIN="$BATS_TEST_TMPDIR/fake-mise"
  create_fake_mise "$MISE_BIN"
}

teardown() {
  rm -rf "$TEST_HOME"
}

create_fake_mise() {
  local fake_mise="$1"

  cat > "$fake_mise" <<'MOCK'
#!/usr/bin/env bash
if [ "${1:-}" = "-C" ] && [ "${3:-}" = "which" ]; then
  if [ "${2:-}" = "${FAKE_MISE_CWD:-}" ] && [ "${4:-}" = "${FAKE_MISE_NAME:-}" ]; then
    printf '%s\n' "$FAKE_MISE_PATH"
    exit 0
  fi
  echo "mise ERROR ${4:-} is not active" >&2
  exit 1
fi

echo "unexpected fake mise invocation: $*" >&2
exit 127
MOCK
  chmod +x "$fake_mise"
}

create_managed_mise_shim() {
  local repo_dir="$1"
  local executable="$2"

  mkdir -p "$repo_dir" "$(dirname "$executable")"
  cat > "$executable" <<SHIM
#!/usr/bin/env bash
# managed by shiv
REPO="$repo_dir"
exec mise -C "\$REPO" run -q "\$@"
SHIM
  chmod +x "$executable"
}

create_global_package() {
  local name="$1"
  local repo_dir="$2"
  shift 2

  mkdir -p "$repo_dir"
  shiv_register "$name" "$repo_dir" "$@"
}

run_which_from() {
  local caller_dir="$1"
  local name="$2"

  mkdir -p "$caller_dir"
  cd "$caller_dir"
  shiv which "$name" 2>&1
}

@test "which: current mise-scoped shiv package wins over global registry" {
  local caller_dir="$TEST_HOME/project"
  local global_repo="$SHIV_PACKAGES_DIR/alpha-global"
  local mise_repo="$TEST_HOME/.local/share/mise/installs/shiv-alpha/1.0.0/packages/alpha"
  local mise_executable="$TEST_HOME/.local/share/mise/installs/shiv-alpha/1.0.0/bin/alpha"

  create_global_package "alpha" "$global_repo"
  create_managed_mise_shim "$mise_repo" "$mise_executable"

  export FAKE_MISE_CWD="$caller_dir"
  export FAKE_MISE_NAME="alpha"
  export FAKE_MISE_PATH="$mise_executable"

  run run_which_from "$caller_dir" "alpha"
  [ "$status" -eq 0 ]
  [ "$output" = "$mise_repo" ]
}

@test "which: current mise-scoped shiv package resolves without global registry entry" {
  local caller_dir="$TEST_HOME/project"
  local mise_repo="$TEST_HOME/.local/share/mise/installs/shiv-bravo/2.0.0/packages/bravo"
  local mise_executable="$TEST_HOME/.local/share/mise/installs/shiv-bravo/2.0.0/bin/bravo"

  create_managed_mise_shim "$mise_repo" "$mise_executable"

  export FAKE_MISE_CWD="$caller_dir"
  export FAKE_MISE_NAME="bravo"
  export FAKE_MISE_PATH="$mise_executable"

  run run_which_from "$caller_dir" "bravo"
  [ "$status" -eq 0 ]
  [ "$output" = "$mise_repo" ]
}

@test "which: falls back to global registry when mise has no active shiv package" {
  local caller_dir="$TEST_HOME/project"
  local global_repo="$SHIV_PACKAGES_DIR/charlie"

  create_global_package "charlie" "$global_repo"

  unset FAKE_MISE_CWD FAKE_MISE_NAME FAKE_MISE_PATH

  run run_which_from "$caller_dir" "charlie"
  [ "$status" -eq 0 ]
  [ "$output" = "$global_repo" ]
}

@test "which: global alias fallback still resolves" {
  local caller_dir="$TEST_HOME/project"
  local global_repo="$SHIV_PACKAGES_DIR/delta"

  create_global_package "delta" "$global_repo" "d"

  unset FAKE_MISE_CWD FAKE_MISE_NAME FAKE_MISE_PATH

  run run_which_from "$caller_dir" "d"
  [ "$status" -eq 0 ]
  [ "$output" = "$global_repo" ]
}
