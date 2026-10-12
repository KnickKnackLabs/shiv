#!/usr/bin/env bats

load helpers

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

@test "shim: default global cache stays fixed at its generation-time XDG path" {
  local repo_dir generation_xdg runtime_xdg task_map
  repo_dir=$(create_resolve_repo "mytool")
  generation_xdg="$TEST_HOME/generation-cache"
  runtime_xdg="$TEST_HOME/runtime-cache"

  unset SHIV_CACHE_DIR
  export XDG_CACHE_HOME="$generation_xdg"
  source "$REPO_DIR/lib/cache.sh"
  [ "$SHIV_CACHE_DIR" = "$generation_xdg/shiv" ]

  shiv_create_shim "mytool" "$repo_dir"
  task_map="$generation_xdg/shiv/tasks/mytool"
  mkdir -p "$(dirname "$task_map")" "$runtime_xdg/shiv/tasks"
  printf '%s\n' "dev test unit" > "$task_map"
  printf '%s\n' "stale task" > "$runtime_xdg/shiv/tasks/mytool"

  run env -u SHIV_SKIP_CACHE XDG_CACHE_HOME="$runtime_xdg" "$SHIV_BIN_DIR/mytool" dev test unit
  [ "$status" -eq 0 ]
  [[ "$output" == *"DEV_TEST_UNIT"* ]]

  rm -f "$task_map"
  run env -u SHIV_SKIP_CACHE XDG_CACHE_HOME="$runtime_xdg" "$SHIV_BIN_DIR/mytool" dev test unit
  [ "$status" -eq 0 ]
  [[ "$output" == *"DEV_TEST_UNIT"* ]]
  grep -q '^dev test unit$' "$task_map"
  grep -q '^stale task$' "$runtime_xdg/shiv/tasks/mytool"
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
