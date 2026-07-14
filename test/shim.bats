#!/usr/bin/env bats
# Shim runtime behavior tests — <PACKAGE>_CALLER_PWD propagation, default task, etc.

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

# ============================================================================
# <PACKAGE>_CALLER_PWD propagation
# ============================================================================

@test "shim: template uses unconditional package-specific caller assignment" {
  local repo_dir
  repo_dir=$(create_caller_repo "myapp")
  shiv install myapp "$repo_dir" 2>/dev/null

  grep -q 'MYAPP_CALLER_PWD="$PWD"' "$SHIV_BIN_DIR/myapp"
  ! grep -q 'export CALLER_PWD=' "$SHIV_BIN_DIR/myapp"
}

@test "shim: package-specific caller var reflects actual cwd" {
  local repo_dir
  repo_dir=$(create_caller_repo "myapp")
  shiv install myapp "$repo_dir" 2>/dev/null

  run bash -c "cd /tmp && '$SHIV_BIN_DIR/myapp' show-caller"
  [ "$status" -eq 0 ]
  [[ "$output" == *"/tmp"* ]]
}

@test "shim: package-specific caller var overrides stale value from environment" {
  local repo_dir
  repo_dir=$(create_caller_repo "myapp")
  shiv install myapp "$repo_dir" 2>/dev/null

  # Even if MYAPP_CALLER_PWD is set in the environment, the shim should use $PWD
  run bash -c "export MYAPP_CALLER_PWD='/some/stale/dir' && cd /tmp && '$SHIV_BIN_DIR/myapp' show-caller"
  [ "$status" -eq 0 ]
  [[ "$output" == *"/tmp"* ]]
}

@test "shim: caller var name is sanitized from package name" {
  local repo_dir="$TEST_HOME/repos/my-tool"

  mkdir -p "$repo_dir/.mise/tasks"
  git -C "$repo_dir" init -q -b main
  git -C "$repo_dir" config user.email "test@test.com"
  git -C "$repo_dir" config user.name "Test"
  echo '[tools]' > "$repo_dir/mise.toml"
  cat > "$repo_dir/.mise/tasks/show-caller" <<'TASK'
#!/usr/bin/env bash
#MISE description="Print MY_TOOL_CALLER_PWD"
echo "$MY_TOOL_CALLER_PWD"
TASK
  chmod +x "$repo_dir/.mise/tasks/show-caller"
  git -C "$repo_dir" add .
  git -C "$repo_dir" commit -q -m "init"
  mise trust "$repo_dir/mise.toml" 2>/dev/null
  mkdir -p "$SHIV_CACHE_DIR/completions"
  printf 'show-caller\tPrint MY_TOOL_CALLER_PWD\n' > "$SHIV_CACHE_DIR/completions/my-tool.cache"

  shiv install my-tool "$repo_dir" 2>/dev/null

  grep -q 'MY_TOOL_CALLER_PWD="$PWD"' "$SHIV_BIN_DIR/my-tool"
  run bash -c "cd /tmp && '$SHIV_BIN_DIR/my-tool' show-caller"
  [ "$status" -eq 0 ]
  [[ "$output" == *"/tmp"* ]]
}

# ============================================================================
# tasks interception
# ============================================================================

@test "shim: 'tasks' lists available local tasks in formatted output" {
  local repo_dir
  repo_dir=$(create_caller_repo "myapp")
  shiv install myapp "$repo_dir" 2>/dev/null

  run "$SHIV_BIN_DIR/myapp" tasks
  [ "$status" -eq 0 ]
  [[ "$output" == *"Group"* ]]
  [[ "$output" == *"Task"* ]]
  [[ "$output" == *"Aliases"* ]]
  [[ "$output" == *"Description"* ]]
  [[ "$output" == *"root"* ]]
  [[ "$output" == *"show-caller"* ]]
  [[ "$output" == *"Print MYAPP_CALLER_PWD"* ]]
  [[ "$output" != *"mise-config"* ]]
  [[ "$output" == *"override"* ]]
}

@test "shim: 'tasks' excludes parent mise tasks" {
  local repo_dir parent_dir
  repo_dir=$(create_caller_repo "myapp")
  parent_dir=$(dirname "$repo_dir")

  mkdir -p "$parent_dir/.mise/tasks"
  echo '[tools]' > "$parent_dir/mise.toml"
  cat > "$parent_dir/.mise/tasks/parent-task" <<'TASK'
#!/usr/bin/env bash
#MISE description="Parent task should not leak"
echo parent
TASK
  chmod +x "$parent_dir/.mise/tasks/parent-task"
  mise trust "$parent_dir/mise.toml" 2>/dev/null

  shiv install myapp "$repo_dir" 2>/dev/null

  run "$SHIV_BIN_DIR/myapp" tasks
  [ "$status" -eq 0 ]
  [[ "$output" == *"show-caller"* ]]
  [[ "$output" != *"parent-task"* ]]
  [[ "$output" != *"Parent task should not leak"* ]]
}

@test "shim: --help without package help renders only package-local tasks" {
  local repo_dir parent_dir
  repo_dir=$(create_caller_repo "myapp")
  parent_dir=$(dirname "$repo_dir")

  mkdir -p "$parent_dir/.mise/tasks"
  echo '[tools]' > "$parent_dir/mise.toml"
  cat > "$parent_dir/.mise/tasks/parent-task" <<'TASK'
#!/usr/bin/env bash
#MISE description="Parent task should not leak"
echo parent
TASK
  chmod +x "$parent_dir/.mise/tasks/parent-task"
  mise trust "$parent_dir/mise.toml" 2>/dev/null

  shiv install myapp "$repo_dir" 2>/dev/null

  run "$SHIV_BIN_DIR/myapp" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Group"* ]]
  [[ "$output" == *"Task"* ]]
  [[ "$output" == *"show-caller"* ]]
  [[ "$output" != *"parent-task"* ]]
  [[ "$output" != *"Parent task should not leak"* ]]
}

@test "shim: tasks without jq fails closed instead of leaking parent tasks" {
  local repo_dir parent_dir bin_dir
  repo_dir=$(create_caller_repo "myapp")
  parent_dir=$(dirname "$repo_dir")

  mkdir -p "$parent_dir/.mise/tasks"
  echo '[tools]' > "$parent_dir/mise.toml"
  cat > "$parent_dir/.mise/tasks/parent-task" <<'TASK'
#!/usr/bin/env bash
#MISE description="Parent task should not leak"
echo parent
TASK
  chmod +x "$parent_dir/.mise/tasks/parent-task"
  mise trust "$parent_dir/mise.toml" 2>/dev/null

  shiv install myapp "$repo_dir" 2>/dev/null

  bin_dir="$BATS_TEST_TMPDIR/no-jq-bin"
  mkdir -p "$bin_dir"
  ln -s "$(command -v mise)" "$bin_dir/mise"
  ln -s "$(command -v env)" "$bin_dir/env"
  ln -s "$(command -v bash)" "$bin_dir/bash"
  ln -s "$(command -v basename)" "$bin_dir/basename"

  run env PATH="$bin_dir" "$SHIV_BIN_DIR/myapp" tasks
  [ "$status" -eq 1 ]
  [[ "$output" == *"jq not found"* ]]
  [[ "$output" != *"parent-task"* ]]
  [[ "$output" != *"Parent task should not leak"* ]]
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
# help interception
# ============================================================================

create_named_default_repo() {
  local name="$1"
  local repo_dir="$TEST_HOME/repos/$name"

  mkdir -p "$repo_dir/.mise/tasks"
  git -C "$repo_dir" init -q -b main
  git -C "$repo_dir" config user.email "test@test.com"
  git -C "$repo_dir" config user.name "Test"

  echo '[tools]' > "$repo_dir/mise.toml"

  cat > "$repo_dir/.mise/tasks/$name" <<'TASK'
#!/usr/bin/env bash
#MISE description="Named default command"
#USAGE arg "[message]" help="Message to print"
echo "NAMED_DEFAULT $*"
TASK
  chmod +x "$repo_dir/.mise/tasks/$name"

  git -C "$repo_dir" add .
  git -C "$repo_dir" commit -q -m "init"
  mise trust "$repo_dir/mise.toml" 2>/dev/null

  echo "$repo_dir"
}

@test "shim: --help routes to named default task help" {
  local repo_dir
  repo_dir=$(create_named_default_repo "myapp")
  shiv install myapp "$repo_dir" 2>/dev/null

  run "$SHIV_BIN_DIR/myapp" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Message to print"* ]]
  [[ "$output" != *"show-caller"* ]]
}

@test "shim: package help task handles --help when present" {
  local repo_dir
  repo_dir=$(create_caller_repo "myapp")

  cat > "$repo_dir/.mise/tasks/help" <<'TASK'
#!/usr/bin/env bash
#MISE description="Package help"
echo "PACKAGE_HELP_OUTPUT"
TASK
  chmod +x "$repo_dir/.mise/tasks/help"
  git -C "$repo_dir" add . && git -C "$repo_dir" commit -q -m "add help task"

  shiv install myapp "$repo_dir" 2>/dev/null

  run "$SHIV_BIN_DIR/myapp" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"PACKAGE_HELP_OUTPUT"* ]]
}

@test "shim: package help task handles help subcommand when present" {
  local repo_dir
  repo_dir=$(create_caller_repo "myapp")

  cat > "$repo_dir/.mise/tasks/help" <<'TASK'
#!/usr/bin/env bash
#MISE description="Package help"
echo "PACKAGE_HELP_OUTPUT"
TASK
  chmod +x "$repo_dir/.mise/tasks/help"
  git -C "$repo_dir" add . && git -C "$repo_dir" commit -q -m "add help task"

  shiv install myapp "$repo_dir" 2>/dev/null

  run "$SHIV_BIN_DIR/myapp" help
  [ "$status" -eq 0 ]
  [[ "$output" == *"PACKAGE_HELP_OUTPUT"* ]]
}

@test "shim: --help falls back to formatted local task list" {
  local repo_dir
  repo_dir=$(create_caller_repo "myapp")
  shiv install myapp "$repo_dir" 2>/dev/null

  run "$SHIV_BIN_DIR/myapp" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Group"* ]]
  [[ "$output" == *"Task"* ]]
  [[ "$output" == *"show-caller"* ]]
  [[ "$output" != *"mise-config"* ]]
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
  SHIV_SKIP_CACHE= shiv_cache_task_map "$name" "$repo_dir"
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

@test "shim: install-local task map ignores conflicting runtime XDG cache" {
  local repo_dir runtime_cache
  repo_dir=$(create_resolve_repo "mytool")
  shiv install mytool "$repo_dir" 2>/dev/null
  populate_task_map "mytool" "$repo_dir"

  runtime_cache="$TEST_HOME/runtime-cache"
  mkdir -p "$runtime_cache/shiv/tasks"
  printf '%s\n' "stale task" > "$runtime_cache/shiv/tasks/mytool"

  run env XDG_CACHE_HOME="$runtime_cache" "$SHIV_BIN_DIR/mytool" dev test unit
  [ "$status" -eq 0 ]
  [[ "$output" == *"DEV_TEST_UNIT"* ]]
}

@test "shim: same package shims keep separate install-local task maps" {
  local repo_dir first_bin first_cache second_bin second_cache runtime_cache
  repo_dir=$(create_resolve_repo "mytool")
  first_bin="$TEST_HOME/versions/one/bin"
  first_cache="$TEST_HOME/versions/one/cache"
  second_bin="$TEST_HOME/versions/two/bin"
  second_cache="$TEST_HOME/versions/two/cache"
  runtime_cache="$TEST_HOME/runtime-cache"

  SHIV_BIN_DIR="$first_bin" SHIV_CACHE_DIR="$first_cache" shiv_create_shim "mytool" "$repo_dir"
  mkdir -p "$first_cache/tasks"
  printf '%s\n' "dev test unit" > "$first_cache/tasks/mytool"

  SHIV_BIN_DIR="$second_bin" SHIV_CACHE_DIR="$second_cache" shiv_create_shim "mytool" "$repo_dir"
  mkdir -p "$second_cache/tasks" "$runtime_cache/shiv/tasks"
  printf '%s\n' "greet loud" > "$second_cache/tasks/mytool"
  printf '%s\n' "stale task" > "$runtime_cache/shiv/tasks/mytool"

  run env XDG_CACHE_HOME="$runtime_cache" "$first_bin/mytool" dev test unit
  [ "$status" -eq 0 ]
  [[ "$output" == *"DEV_TEST_UNIT"* ]]

  run env XDG_CACHE_HOME="$runtime_cache" "$second_bin/mytool" greet loud
  [ "$status" -eq 0 ]
  [[ "$output" == *"GREET_LOUD"* ]]
}

@test "shim: tasks groups colon-namespaced tasks" {
  local repo_dir
  repo_dir=$(create_resolve_repo "mytool")
  shiv install mytool "$repo_dir" 2>/dev/null

  run "$SHIV_BIN_DIR/mytool" tasks
  [ "$status" -eq 0 ]
  [[ "$output" == *"Group"* ]]
  [[ "$output" == *"root"*"greet"* ]]
  [[ "$output" == *"greet"*"loud"* ]]
  [[ "$output" == *"dev"*"test:unit"* ]]
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

@test "shim: cache miss generates task map in install-local cache" {
  local repo_dir runtime_cache
  repo_dir=$(create_resolve_repo "mytool")
  shiv install mytool "$repo_dir" 2>/dev/null

  runtime_cache="$TEST_HOME/runtime-cache"
  [ ! -f "$SHIV_CACHE_DIR/tasks/mytool" ]
  [ ! -f "$runtime_cache/shiv/tasks/mytool" ]

  run env -u SHIV_SKIP_CACHE XDG_CACHE_HOME="$runtime_cache" "$SHIV_BIN_DIR/mytool" dev test unit
  [ "$status" -eq 0 ]
  [[ "$output" == *"DEV_TEST_UNIT"* ]]

  [ -f "$SHIV_CACHE_DIR/tasks/mytool" ]
  [ ! -f "$runtime_cache/shiv/tasks/mytool" ]
}

@test "shim: cache miss and execution ignore inherited mise config override" {
  local repo_dir parent_config
  repo_dir=$(create_resolve_repo "mytool")
  shiv install mytool "$repo_dir" 2>/dev/null

  parent_config="$TEST_HOME/parent-config.toml"
  cat > "$parent_config" <<'TOML'
[tasks.parent-only]
description = "Parent task should not leak"
run = "echo PARENT_ONLY"
TOML
  mise trust "$parent_config" 2>/dev/null

  [ ! -f "$SHIV_CACHE_DIR/tasks/mytool" ]

  run env -u SHIV_SKIP_CACHE \
    MISE_OVERRIDE_CONFIG_FILENAMES="$parent_config" \
    XDG_CACHE_HOME="$TEST_HOME/.cache" \
    "$SHIV_BIN_DIR/mytool" dev test unit
  [ "$status" -eq 0 ]
  [[ "$output" == *"DEV_TEST_UNIT"* ]]
  [[ "$output" != *"PARENT_ONLY"* ]]

  grep -q "^dev test unit$" "$SHIV_CACHE_DIR/tasks/mytool"
  ! grep -q "parent-only" "$SHIV_CACHE_DIR/tasks/mytool"
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
