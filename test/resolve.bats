#!/usr/bin/env bats
# shiv space-to-colon resolution test suite
#
# Tests the task map cache (Phase 1) and will later include
# matching/resolution logic (Phase 2).

REPO_DIR="$BATS_TEST_DIRNAME/.."

setup() {
  source "$REPO_DIR/lib/shim.sh"

  # Use a temporary home for isolation
  export TEST_HOME="$BATS_TMPDIR/shiv-test-$$"
  mkdir -p "$TEST_HOME"

  # Override shiv paths to use test home
  export SHIV_BIN_DIR="$TEST_HOME/.local/bin"
  export SHIV_DATA_DIR="$TEST_HOME/.local/share/shiv"
  export SHIV_PACKAGES_DIR="$SHIV_DATA_DIR/packages"
  export SHIV_CONFIG_DIR="$TEST_HOME/.config/shiv"
  export SHIV_CACHE_DIR="$TEST_HOME/.cache/shiv"
  export SHIV_REGISTRY="$SHIV_CONFIG_DIR/registry.json"
  export SHIV_SOURCES_DIR="$SHIV_CONFIG_DIR/sources"

  # Register shiv itself as a test package
  shiv_init_registry
  shiv_register "shiv" "$REPO_DIR"
}

teardown() {
  rm -rf "$TEST_HOME"
}

# ============================================================================
# Task map cache generation
# ============================================================================

@test "task-map: shiv_cache_task_map creates cache file" {
  shiv_cache_task_map "shiv" "$REPO_DIR"
  [ -f "$SHIV_CACHE_DIR/tasks/shiv" ]
}

@test "task-map: cache contains known tasks with colons converted to spaces" {
  shiv_cache_task_map "shiv" "$REPO_DIR"
  grep -q "^install$" "$SHIV_CACHE_DIR/tasks/shiv"
  grep -q "^list$" "$SHIV_CACHE_DIR/tasks/shiv"
  grep -q "^test completions$" "$SHIV_CACHE_DIR/tasks/shiv"
  grep -q "^test doctor$" "$SHIV_CACHE_DIR/tasks/shiv"
}

@test "task-map: cache format is one space-separated task path per line" {
  shiv_cache_task_map "shiv" "$REPO_DIR"
  # No colons should appear in the task map
  ! grep -q ":" "$SHIV_CACHE_DIR/tasks/shiv"
  # No empty lines
  ! grep -q "^$" "$SHIV_CACHE_DIR/tasks/shiv"
  # No tabs
  ! grep -qP "\t" "$SHIV_CACHE_DIR/tasks/shiv"
}

@test "task-map: cache includes hidden tasks" {
  # Create a fake package with a hidden task
  local fake_dir="$TEST_HOME/fake-pkg"
  mkdir -p "$fake_dir/.mise/tasks"
  cat > "$fake_dir/mise.toml" <<'EOF'
[tasks.visible]
run = "echo hi"
[tasks.secret]
run = "echo hidden"
hide = true
EOF
  mise trust -C "$fake_dir" -q 2>/dev/null
  shiv_cache_task_map "fakepkg" "$fake_dir"
  grep -q "^visible$" "$SHIV_CACHE_DIR/tasks/fakepkg"
  grep -q "^secret$" "$SHIV_CACHE_DIR/tasks/fakepkg"
}

@test "task-map: deep nesting translates all colons to spaces" {
  local fake_dir="$TEST_HOME/deep-pkg"
  mkdir -p "$fake_dir/.mise/tasks/a/b/c"
  cat > "$fake_dir/mise.toml" <<'EOF'
EOF
  echo '#!/usr/bin/env bash' > "$fake_dir/.mise/tasks/a/b/c/d"
  chmod +x "$fake_dir/.mise/tasks/a/b/c/d"
  mise trust -C "$fake_dir" -q 2>/dev/null
  shiv_cache_task_map "deeppkg" "$fake_dir"
  grep -q "^a b c d$" "$SHIV_CACHE_DIR/tasks/deeppkg"
}

@test "task-map: single-word tasks have no spaces" {
  shiv_cache_task_map "shiv" "$REPO_DIR"
  # 'install' should appear as exactly 'install' — no leading/trailing spaces
  grep -q "^install$" "$SHIV_CACHE_DIR/tasks/shiv"
  grep -q "^list$" "$SHIV_CACHE_DIR/tasks/shiv"
  grep -q "^doctor$" "$SHIV_CACHE_DIR/tasks/shiv"
  # Single-word lines should have zero spaces
  while IFS= read -r line; do
    local word_count
    word_count=$(echo "$line" | wc -w | tr -d ' ')
    if [ "$word_count" -eq 1 ]; then
      [[ "$line" != *" "* ]]
    fi
  done < "$SHIV_CACHE_DIR/tasks/shiv"
}

@test "task-map: idempotent — second call overwrites cleanly" {
  shiv_cache_task_map "shiv" "$REPO_DIR"
  local first_content
  first_content=$(cat "$SHIV_CACHE_DIR/tasks/shiv")
  shiv_cache_task_map "shiv" "$REPO_DIR"
  local second_content
  second_content=$(cat "$SHIV_CACHE_DIR/tasks/shiv")
  [ "$first_content" = "$second_content" ]
}

@test "task-map: no .tmp file left behind on success" {
  shiv_cache_task_map "shiv" "$REPO_DIR"
  [ ! -f "$SHIV_CACHE_DIR/tasks/shiv.tmp" ]
}

@test "task-map: empty output does not create cache file" {
  # Point at an empty directory with no tasks
  local empty_dir="$TEST_HOME/empty-pkg"
  mkdir -p "$empty_dir"
  cat > "$empty_dir/mise.toml" <<'EOF'
EOF
  shiv_cache_task_map "emptypkg" "$empty_dir"
  [ ! -f "$SHIV_CACHE_DIR/tasks/emptypkg" ]
  [ ! -f "$SHIV_CACHE_DIR/tasks/emptypkg.tmp" ]
}

@test "task-map: invalid repo dir does not create cache file" {
  shiv_cache_task_map "bogus" "/nonexistent/path"
  [ ! -f "$SHIV_CACHE_DIR/tasks/bogus" ]
}

# ============================================================================
# Task map cleanup
# ============================================================================

@test "task-map: shiv_cache_remove deletes task map file" {
  shiv_cache_task_map "shiv" "$REPO_DIR"
  [ -f "$SHIV_CACHE_DIR/tasks/shiv" ]
  shiv_cache_remove "shiv"
  [ ! -f "$SHIV_CACHE_DIR/tasks/shiv" ]
}

@test "task-map: shiv_cache_remove also deletes completions cache" {
  shiv_cache_tasks "shiv" "$REPO_DIR"
  shiv_cache_task_map "shiv" "$REPO_DIR"
  [ -f "$SHIV_CACHE_DIR/completions/shiv.cache" ]
  [ -f "$SHIV_CACHE_DIR/tasks/shiv" ]
  shiv_cache_remove "shiv"
  [ ! -f "$SHIV_CACHE_DIR/completions/shiv.cache" ]
  [ ! -f "$SHIV_CACHE_DIR/tasks/shiv" ]
}

@test "task-map: shiv_cache_remove is safe when task map doesn't exist" {
  run shiv_cache_remove "nonexistent"
  [ "$status" -eq 0 ]
}

# ============================================================================
# Multiple packages
# ============================================================================

@test "task-map: separate cache files per package" {
  shiv_register "faketool" "$REPO_DIR"
  shiv_cache_task_map "shiv" "$REPO_DIR"
  shiv_cache_task_map "faketool" "$REPO_DIR"
  [ -f "$SHIV_CACHE_DIR/tasks/shiv" ]
  [ -f "$SHIV_CACHE_DIR/tasks/faketool" ]
  # Content should be identical (same repo)
  diff "$SHIV_CACHE_DIR/tasks/shiv" "$SHIV_CACHE_DIR/tasks/faketool"
}

# ============================================================================
# Phase 2: shiv_resolve_task — matching logic
# ============================================================================

# Helper: create a synthetic task map file for testing.
# Pure tests — no mise dependency.
_make_task_map() {
  local name="$1"
  shift
  local map_file="$SHIV_CACHE_DIR/tasks/$name"
  mkdir -p "$SHIV_CACHE_DIR/tasks"
  printf "%s\n" "$@" > "$map_file"
  echo "$map_file"
}

# --- Basic resolution ---

@test "resolve: single-word task" {
  local map
  map=$(_make_task_map "mytool" "install" "list" "doctor")
  run shiv_resolve_task "$map" "install"
  [ "$status" -eq 0 ]
  local task args
  task=$(echo "$output" | sed -n '1p')
  args=$(echo "$output" | sed -n '2p')
  [ "$task" = "install" ]
  [ "$args" = "" ]
}

@test "resolve: multi-word task translates to colons" {
  local map
  map=$(_make_task_map "mytool" "agent message" "agent list" "as")
  run shiv_resolve_task "$map" "agent" "message" "foo"
  [ "$status" -eq 0 ]
  local task args
  task=$(echo "$output" | sed -n '1p')
  args=$(echo "$output" | sed -n '2p')
  [ "$task" = "agent:message" ]
  [ "$args" = "foo" ]
}

@test "resolve: multi-word task with multiple remaining args" {
  local map
  map=$(_make_task_map "mytool" "agent message")
  run shiv_resolve_task "$map" "agent" "message" "foo" "bar" "baz"
  [ "$status" -eq 0 ]
  local task args
  task=$(echo "$output" | sed -n '1p')
  args=$(echo "$output" | sed -n '2p')
  [ "$task" = "agent:message" ]
  [ "$args" = "foo bar baz" ]
}

@test "resolve: deep nesting (3+ levels)" {
  local map
  map=$(_make_task_map "mytool" "dev test unit" "dev test integration" "build")
  run shiv_resolve_task "$map" "dev" "test" "unit"
  [ "$status" -eq 0 ]
  local task args
  task=$(echo "$output" | sed -n '1p')
  args=$(echo "$output" | sed -n '2p')
  [ "$task" = "dev:test:unit" ]
  [ "$args" = "" ]
}

@test "resolve: no match returns exit 2" {
  local map
  map=$(_make_task_map "mytool" "install" "list")
  run shiv_resolve_task "$map" "nonexistent" "foo"
  [ "$status" -eq 2 ]
}

@test "resolve: no args returns exit 2" {
  local map
  map=$(_make_task_map "mytool" "install")
  run shiv_resolve_task "$map"
  [ "$status" -eq 2 ]
}

@test "resolve: missing task map file returns exit 2" {
  run shiv_resolve_task "/nonexistent/path" "install"
  [ "$status" -eq 2 ]
}

# --- Longest prefix match ---

@test "resolve: longest prefix wins when no ambiguity" {
  # 'agent message' exists but 'agent' does NOT — no ambiguity
  local map
  map=$(_make_task_map "mytool" "agent message" "agent list" "build")
  run shiv_resolve_task "$map" "agent" "message" "foo"
  [ "$status" -eq 0 ]
  local task args
  task=$(echo "$output" | sed -n '1p')
  args=$(echo "$output" | sed -n '2p')
  [ "$task" = "agent:message" ]
  [ "$args" = "foo" ]
}

@test "resolve: falls back to shorter match when longer doesn't exist" {
  # 'agent' exists, 'agent message' does NOT
  # user types: agent message → matches 'agent' with arg 'message'
  local map
  map=$(_make_task_map "mytool" "agent" "build")
  run shiv_resolve_task "$map" "agent" "message"
  [ "$status" -eq 0 ]
  local task args
  task=$(echo "$output" | sed -n '1p')
  args=$(echo "$output" | sed -n '2p')
  [ "$task" = "agent" ]
  [ "$args" = "message" ]
}

# --- Ambiguity detection ---

@test "resolve: ambiguous when both parent and child task exist" {
  # 'test' exists AND 'test completions' exists
  local map
  map=$(_make_task_map "mytool" "test" "test completions" "test doctor" "install")
  run shiv_resolve_task "$map" "test" "completions"
  [ "$status" -eq 1 ]
  # Error message should mention both tasks
  [[ "$output" == *"Ambiguous"* ]]
  [[ "$output" == *"test:completions"* ]]
  [[ "$output" == *"test"* ]]
  [[ "$output" == *"--"* ]]
}

@test "resolve: ambiguous error message shows disambiguation guidance" {
  local map
  map=$(_make_task_map "mytool" "as" "as zeke")
  run shiv_resolve_task "$map" "as" "zeke"
  [ "$status" -eq 1 ]
  # Should show both -- options
  [[ "$output" == *"as -- zeke"* ]]
  [[ "$output" == *"as zeke --"* ]]
}

@test "resolve: no ambiguity when only child exists (parent absent)" {
  # 'test completions' exists but 'test' does NOT
  local map
  map=$(_make_task_map "mytool" "test completions" "test doctor" "install")
  run shiv_resolve_task "$map" "test" "completions"
  [ "$status" -eq 0 ]
  local task args
  task=$(echo "$output" | sed -n '1p')
  args=$(echo "$output" | sed -n '2p')
  [ "$task" = "test:completions" ]
  [ "$args" = "" ]
}

@test "resolve: single-word match with no children is not ambiguous" {
  local map
  map=$(_make_task_map "mytool" "install" "list" "doctor")
  run shiv_resolve_task "$map" "install" "some-arg"
  [ "$status" -eq 0 ]
  local task args
  task=$(echo "$output" | sed -n '1p')
  args=$(echo "$output" | sed -n '2p')
  [ "$task" = "install" ]
  [ "$args" = "some-arg" ]
}

# --- Double-dash disambiguation ---

@test "resolve: -- before args selects shorter task" {
  local map
  map=$(_make_task_map "mytool" "as" "as zeke")
  run shiv_resolve_task "$map" "as" "--" "zeke"
  [ "$status" -eq 0 ]
  local task args
  task=$(echo "$output" | sed -n '1p')
  args=$(echo "$output" | sed -n '2p')
  [ "$task" = "as" ]
  [ "$args" = "zeke" ]
}

@test "resolve: trailing -- selects full task path with no args" {
  local map
  map=$(_make_task_map "mytool" "as" "as zeke")
  run shiv_resolve_task "$map" "as" "zeke" "--"
  [ "$status" -eq 0 ]
  local task args
  task=$(echo "$output" | sed -n '1p')
  args=$(echo "$output" | sed -n '2p')
  [ "$task" = "as:zeke" ]
  [ "$args" = "" ]
}

@test "resolve: -- with multi-word task and remaining args" {
  local map
  map=$(_make_task_map "mytool" "agent message" "agent" "agent message send")
  run shiv_resolve_task "$map" "agent" "message" "--" "hello" "world"
  [ "$status" -eq 0 ]
  local task args
  task=$(echo "$output" | sed -n '1p')
  args=$(echo "$output" | sed -n '2p')
  [ "$task" = "agent:message" ]
  [ "$args" = "hello world" ]
}

@test "resolve: -- with nonexistent task returns exit 2" {
  local map
  map=$(_make_task_map "mytool" "install" "list")
  run shiv_resolve_task "$map" "nonexistent" "--" "arg"
  [ "$status" -eq 2 ]
}

@test "resolve: bare -- with no task words returns exit 2" {
  local map
  map=$(_make_task_map "mytool" "install")
  run shiv_resolve_task "$map" "--" "install"
  [ "$status" -eq 2 ]
}

# --- Edge cases ---

@test "resolve: exact match consuming all args (no remaining)" {
  local map
  map=$(_make_task_map "mytool" "dev test unit")
  run shiv_resolve_task "$map" "dev" "test" "unit"
  [ "$status" -eq 0 ]
  local task args
  task=$(echo "$output" | sed -n '1p')
  args=$(echo "$output" | sed -n '2p')
  [ "$task" = "dev:test:unit" ]
  [ "$args" = "" ]
}

@test "resolve: partial prefix that doesn't match any task" {
  local map
  map=$(_make_task_map "mytool" "agent message" "agent list")
  # 'agent' alone is not in the map, and 'agent foo' is not either
  run shiv_resolve_task "$map" "agent" "foo"
  [ "$status" -eq 2 ]
}

@test "resolve: task map with single entry" {
  local map
  map=$(_make_task_map "mytool" "hello world")
  run shiv_resolve_task "$map" "hello" "world" "arg1"
  [ "$status" -eq 0 ]
  local task args
  task=$(echo "$output" | sed -n '1p')
  args=$(echo "$output" | sed -n '2p')
  [ "$task" = "hello:world" ]
  [ "$args" = "arg1" ]
}
