#!/usr/bin/env bats
# Shim runtime behavior tests — CALLER_PWD propagation, default task, etc.

REPO_DIR="$BATS_TEST_DIRNAME/.."
load helpers

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

# ============================================================================
# tasks interception
# ============================================================================

@test "shim: 'tasks' lists available tasks when no tasks task exists" {
  local repo_dir
  repo_dir=$(create_caller_repo "myapp")
  shiv install myapp "$repo_dir" 2>/dev/null

  run "$SHIV_BIN_DIR/myapp" tasks
  [ "$status" -eq 0 ]
  [[ "$output" == *"show-caller"* ]]
  [[ "$output" == *"override"* ]]
}

@test "shim: 'tasks' runs the package's tasks task when one exists" {
  local repo_dir
  repo_dir=$(create_caller_repo "myapp")

  # Add a custom 'tasks' task
  cat > "$repo_dir/.mise/tasks/tasks" <<'TASK'
#!/usr/bin/env bash
#MISE description="Custom tasks listing"
echo "CUSTOM_TASKS_OUTPUT"
TASK
  chmod +x "$repo_dir/.mise/tasks/tasks"
  git -C "$repo_dir" add . && git -C "$repo_dir" commit -q -m "add tasks task"

  shiv install myapp "$repo_dir" 2>/dev/null

  run "$SHIV_BIN_DIR/myapp" tasks
  [ "$status" -eq 0 ]
  [[ "$output" == *"CUSTOM_TASKS_OUTPUT"* ]]
  # Should NOT show the override hint
  [[ "$output" != *"override"* ]]
}

# ============================================================================
# Space-to-colon resolution (integration)
# ============================================================================

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
  mkdir -p "$SHIV_CACHE_DIR/tasks"
  mise tasks --json --hidden -C "$repo_dir" 2>/dev/null \
    | jq -r '.[].name | gsub(":"; " ")' > "$SHIV_CACHE_DIR/tasks/$name"
}

@test "shim: spaces resolve to colons end-to-end" {
  local repo_dir
  repo_dir=$(create_resolve_repo "mytool")
  shiv install mytool "$repo_dir" 2>/dev/null
  populate_task_map "mytool" "$repo_dir"

  run "$SHIV_BIN_DIR/mytool" dev test unit
  [ "$status" -eq 0 ]
  [[ "$output" == *"DEV_TEST_UNIT"* ]]
}

@test "shim: spaces resolve with remaining args passed through" {
  local repo_dir
  repo_dir=$(create_resolve_repo "mytool")
  shiv install mytool "$repo_dir" 2>/dev/null
  populate_task_map "mytool" "$repo_dir"

  run "$SHIV_BIN_DIR/mytool" dev test unit myarg
  [ "$status" -eq 0 ]
  [[ "$output" == *"DEV_TEST_UNIT myarg"* ]]
}

@test "shim: ambiguous input errors with guidance" {
  local repo_dir
  repo_dir=$(create_resolve_repo "mytool")
  shiv install mytool "$repo_dir" 2>/dev/null
  populate_task_map "mytool" "$repo_dir"

  run "$SHIV_BIN_DIR/mytool" greet loud
  [ "$status" -eq 1 ]
  [[ "$output" == *"Ambiguous"* ]]
  [[ "$output" == *"--"* ]]
}

@test "shim: -- selects parent task with args" {
  local repo_dir
  repo_dir=$(create_resolve_repo "mytool")
  shiv install mytool "$repo_dir" 2>/dev/null
  populate_task_map "mytool" "$repo_dir"

  run "$SHIV_BIN_DIR/mytool" greet -- loud
  [ "$status" -eq 0 ]
  [[ "$output" == *"GREET loud"* ]]
}

@test "shim: trailing -- selects child task with no args" {
  local repo_dir
  repo_dir=$(create_resolve_repo "mytool")
  shiv install mytool "$repo_dir" 2>/dev/null
  populate_task_map "mytool" "$repo_dir"

  run "$SHIV_BIN_DIR/mytool" greet loud --
  [ "$status" -eq 0 ]
  [[ "$output" == *"GREET_LOUD"* ]]
  [[ "$output" == "GREET_LOUD " ]] || [[ "$output" == "GREET_LOUD" ]]
}

@test "shim: cache miss generates task map on the fly" {
  local repo_dir
  repo_dir=$(create_resolve_repo "mytool")
  shiv install mytool "$repo_dir" 2>/dev/null

  [ ! -f "$SHIV_CACHE_DIR/tasks/mytool" ]

  # The shim uses XDG_CACHE_HOME (not SHIV_CACHE_DIR) for task maps.
  run env -u SHIV_SKIP_CACHE XDG_CACHE_HOME="$TEST_HOME/.cache" "$SHIV_BIN_DIR/mytool" dev test unit
  [ "$status" -eq 0 ]
  [[ "$output" == *"DEV_TEST_UNIT"* ]]

  [ -f "$SHIV_CACHE_DIR/tasks/mytool" ]
}

@test "shim: unresolved input falls through to mise" {
  local repo_dir
  repo_dir=$(create_resolve_repo "mytool")
  shiv install mytool "$repo_dir" 2>/dev/null
  populate_task_map "mytool" "$repo_dir"

  run "$SHIV_BIN_DIR/mytool" nonexistent-thing
  [ "$status" -ne 0 ]
}

@test "shim: colons still work (backward compatible)" {
  local repo_dir
  repo_dir=$(create_resolve_repo "mytool")
  shiv install mytool "$repo_dir" 2>/dev/null
  populate_task_map "mytool" "$repo_dir"

  run "$SHIV_BIN_DIR/mytool" dev:test:unit
  [ "$status" -eq 0 ]
  [[ "$output" == *"DEV_TEST_UNIT"* ]]
}

# ============================================================================
# Default task + subtask ambiguity (shiv#94)
# ============================================================================

# Helper: create a repo with _default (interactive menu) + named subtasks.
# Mimics the pattern from KnickKnackLabs/ask.
create_default_plus_subtasks_repo() {
  local name="$1"
  local repo_dir="$TEST_HOME/repos/$name"

  mkdir -p "$repo_dir/.mise/tasks"
  git -C "$repo_dir" init -q -b main
  git -C "$repo_dir" config user.email "test@test.com"
  git -C "$repo_dir" config user.name "Test"

  echo '[tools]' > "$repo_dir/mise.toml"

  # _default — interactive menu / catch-all
  cat > "$repo_dir/.mise/tasks/_default" <<'TASK'
#!/usr/bin/env bash
#MISE description="Interactive menu"
echo "DEFAULT $*"
TASK
  chmod +x "$repo_dir/.mise/tasks/_default"

  # question — named subtask (alias: q)
  cat > "$repo_dir/.mise/tasks/question" <<'TASK'
#!/usr/bin/env bash
#MISE description="Ask a question"
#MISE alias="q"
echo "QUESTION $*"
TASK
  chmod +x "$repo_dir/.mise/tasks/question"

  # info — another named subtask
  cat > "$repo_dir/.mise/tasks/info" <<'TASK'
#!/usr/bin/env bash
#MISE description="Show info"
echo "INFO $*"
TASK
  chmod +x "$repo_dir/.mise/tasks/info"

  git -C "$repo_dir" add .
  git -C "$repo_dir" commit -q -m "init"
  mise trust "$repo_dir/mise.toml" 2>/dev/null

  echo "$repo_dir"
}

@test "shim: _default runs with no args" {
  local repo_dir
  repo_dir=$(create_default_plus_subtasks_repo "asktool")
  shiv install asktool "$repo_dir" 2>/dev/null
  populate_task_map "asktool" "$repo_dir"

  run "$SHIV_BIN_DIR/asktool"
  [ "$status" -eq 0 ]
  [[ "$output" == *"DEFAULT"* ]]
}

@test "shim: subtask name is ambiguous when _default exists" {
  local repo_dir
  repo_dir=$(create_default_plus_subtasks_repo "asktool")
  shiv install asktool "$repo_dir" 2>/dev/null
  populate_task_map "asktool" "$repo_dir"

  run "$SHIV_BIN_DIR/asktool" question hello
  [ "$status" -eq 1 ]
  [[ "$output" == *"Ambiguous"* ]]
  [[ "$output" == *"--"* ]]
}

@test "shim: subtask alone is ambiguous when _default exists" {
  local repo_dir
  repo_dir=$(create_default_plus_subtasks_repo "asktool")
  shiv install asktool "$repo_dir" 2>/dev/null
  populate_task_map "asktool" "$repo_dir"

  run "$SHIV_BIN_DIR/asktool" info
  [ "$status" -eq 1 ]
  [[ "$output" == *"Ambiguous"* ]]
}

@test "shim: -- before subtask name routes to _default" {
  local repo_dir
  repo_dir=$(create_default_plus_subtasks_repo "asktool")
  shiv install asktool "$repo_dir" 2>/dev/null
  populate_task_map "asktool" "$repo_dir"

  run "$SHIV_BIN_DIR/asktool" -- question hello
  [ "$status" -eq 0 ]
  [[ "$output" == *"DEFAULT question hello"* ]]
}

@test "shim: subtask -- args routes to subtask" {
  local repo_dir
  repo_dir=$(create_default_plus_subtasks_repo "asktool")
  shiv install asktool "$repo_dir" 2>/dev/null
  populate_task_map "asktool" "$repo_dir"

  run "$SHIV_BIN_DIR/asktool" question -- hello
  [ "$status" -eq 0 ]
  [[ "$output" == *"QUESTION"* ]]
  [[ "$output" == *"hello"* ]]
}

@test "shim: unrecognized arg falls through to _default" {
  local repo_dir
  repo_dir=$(create_default_plus_subtasks_repo "asktool")
  shiv install asktool "$repo_dir" 2>/dev/null
  populate_task_map "asktool" "$repo_dir"

  run "$SHIV_BIN_DIR/asktool" "summarize this"
  [ "$status" -eq 0 ]
  [[ "$output" == *"DEFAULT summarize this"* ]]
}

@test "shim: flag args fall through to _default" {
  local repo_dir
  repo_dir=$(create_default_plus_subtasks_repo "asktool")
  shiv install asktool "$repo_dir" 2>/dev/null
  populate_task_map "asktool" "$repo_dir"

  run "$SHIV_BIN_DIR/asktool" -m sonnet
  [ "$status" -eq 0 ]
  [[ "$output" == *"DEFAULT -m sonnet"* ]]
}

@test "shim: -- with no further args runs _default with no args" {
  local repo_dir
  repo_dir=$(create_default_plus_subtasks_repo "asktool")
  shiv install asktool "$repo_dir" 2>/dev/null
  populate_task_map "asktool" "$repo_dir"

  run "$SHIV_BIN_DIR/asktool" --
  [ "$status" -eq 0 ]
  [[ "$output" == *"DEFAULT"* ]]
}
