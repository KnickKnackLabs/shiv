#!/usr/bin/env bats

load helpers

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
