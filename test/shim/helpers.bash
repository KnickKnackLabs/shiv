# Shared setup and reused fixtures for generated-shim suites.

REPO_DIR="$BATS_TEST_DIRNAME/../.."
load ../helpers

setup() {
  source "$REPO_DIR/lib/shim.sh"

  export TEST_HOME="$BATS_TEST_TMPDIR/shiv"
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

# Helper: create a repo with a task that echoes MYAPP_CALLER_PWD
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
#MISE description="Print MYAPP_CALLER_PWD"
echo "$MYAPP_CALLER_PWD"
TASK
  chmod +x "$repo_dir/.mise/tasks/show-caller"

  git -C "$repo_dir" add .
  git -C "$repo_dir" commit -q -m "init"
  mise trust "$repo_dir/mise.toml" 2>/dev/null

  mkdir -p "$SHIV_CACHE_DIR/completions"
  printf 'show-caller\tPrint MYAPP_CALLER_PWD\n' > "$SHIV_CACHE_DIR/completions/$name.cache"

  echo "$repo_dir"
}

# Helper: create a repo with nested tasks for resolution testing.
# Creates: greet (echo GREET), greet:loud (echo GREET_LOUD),
# and dev:test:unit (echoes args).
create_resolve_repo() {
  local name="$1"
  local repo_dir="$TEST_HOME/repos/$name"

  mkdir -p "$repo_dir/.mise/tasks/greet" "$repo_dir/.mise/tasks/dev/test"
  git -C "$repo_dir" init -q -b main
  git -C "$repo_dir" config user.email "test@test.com"
  git -C "$repo_dir" config user.name "Test"

  echo '[tools]' > "$repo_dir/mise.toml"

  # greet — a task that is also a prefix of greet:loud
  cat > "$repo_dir/.mise/tasks/greet/_default" <<'TASK'
#!/usr/bin/env bash
#MISE description="Say hello"
echo "GREET $*"
TASK
  chmod +x "$repo_dir/.mise/tasks/greet/_default"

  # greet:loud — child task
  cat > "$repo_dir/.mise/tasks/greet/loud" <<'TASK'
#!/usr/bin/env bash
#MISE description="Say hello loudly"
echo "GREET_LOUD $*"
TASK
  chmod +x "$repo_dir/.mise/tasks/greet/loud"

  # dev:test:unit — deep nesting
  cat > "$repo_dir/.mise/tasks/dev/test/unit" <<'TASK'
#!/usr/bin/env bash
#MISE description="Run unit tests"
echo "DEV_TEST_UNIT $*"
TASK
  chmod +x "$repo_dir/.mise/tasks/dev/test/unit"

  git -C "$repo_dir" add .
  git -C "$repo_dir" commit -q -m "init"
  mise trust "$repo_dir/mise.toml" 2>/dev/null

  echo "$repo_dir"
}

# Helper: pre-populate the task map cache for a package.
# This is called separately from `shiv install` so that unit tests exercise
# resolution against a known task map without depending on the install hook's
# cache generation (which requires mise + jq at install time). The integration
# test "cache miss generates task map on the fly" covers that path.
populate_task_map() {
  local name="$1" repo_dir="$2"
  SHIV_SKIP_CACHE='' shiv_cache_task_map "$name" "$repo_dir"
}
