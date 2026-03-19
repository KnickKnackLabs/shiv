#!/usr/bin/env bats
# Shim runtime behavior tests — CALLER_PWD propagation, default task, etc.

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

  export SHIV_SKIP_CACHE=1
}

teardown() {
  rm -rf "$TEST_HOME"
}

# Helper: create a repo with a task that echoes CALLER_PWD
create_caller_repo() {
  local name="$1"
  local repo_dir="$TEST_HOME/repos/$name"

  mkdir -p "$repo_dir/.mise/tasks"
  git -C "$repo_dir" init -q -b main
  git -C "$repo_dir" config user.email "test@test.com"
  git -C "$repo_dir" config user.name "Test"

  echo '[tools]' > "$repo_dir/mise.toml"

  cat > "$repo_dir/.mise/tasks/show-caller" <<'TASK'
#!/usr/bin/env bash
#MISE description="Print CALLER_PWD"
echo "$CALLER_PWD"
TASK
  chmod +x "$repo_dir/.mise/tasks/show-caller"

  git -C "$repo_dir" add .
  git -C "$repo_dir" commit -q -m "init"
  mise trust "$repo_dir/mise.toml" 2>/dev/null

  mkdir -p "$SHIV_CACHE_DIR/completions"
  printf 'show-caller\tPrint CALLER_PWD\n' > "$SHIV_CACHE_DIR/completions/$name.cache"

  echo "$repo_dir"
}

# ============================================================================
# CALLER_PWD propagation
# ============================================================================

@test "shim: template uses unconditional CALLER_PWD assignment" {
  local repo_dir
  repo_dir=$(create_caller_repo "myapp")
  shiv install myapp "$repo_dir" 2>/dev/null

  grep -q 'CALLER_PWD="$PWD"' "$SHIV_BIN_DIR/myapp"
}

@test "shim: CALLER_PWD reflects actual cwd" {
  local repo_dir
  repo_dir=$(create_caller_repo "myapp")
  shiv install myapp "$repo_dir" 2>/dev/null

  run bash -c "cd /tmp && '$SHIV_BIN_DIR/myapp' show-caller"
  [ "$status" -eq 0 ]
  [[ "$output" == *"/tmp"* ]]
}

@test "shim: CALLER_PWD overrides stale value from environment" {
  local repo_dir
  repo_dir=$(create_caller_repo "myapp")
  shiv install myapp "$repo_dir" 2>/dev/null

  # Even if CALLER_PWD is set in the environment, the shim should use $PWD
  run bash -c "export CALLER_PWD='/some/stale/dir' && cd /tmp && '$SHIV_BIN_DIR/myapp' show-caller"
  [ "$status" -eq 0 ]
  [[ "$output" == *"/tmp"* ]]
}
