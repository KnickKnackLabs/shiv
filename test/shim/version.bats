#!/usr/bin/env bats

load helpers

@test "shim: --version shows the exact tag, branch, and commit age" {
  local repo_dir
  repo_dir=$(create_caller_repo "myapp")
  git -C "$repo_dir" tag --no-sign v1.2.3
  git -C "$repo_dir" -c advice.detachedHead=false checkout --detach v1.2.3
  shiv_create_shim "myapp" "$repo_dir"

  run "$SHIV_BIN_DIR/myapp" --version
  [ "$status" -eq 0 ]
  [[ "$output" == "myapp v1.2.3 (branch: detached, updated: "*" ago)" ]]
}

@test "shim: --version falls back to the short commit" {
  local repo_dir short
  repo_dir=$(create_caller_repo "myapp")
  short=$(git -C "$repo_dir" rev-parse --short HEAD)
  shiv_create_shim "myapp" "$repo_dir"

  run "$SHIV_BIN_DIR/myapp" --version
  [ "$status" -eq 0 ]
  [[ "$output" == "myapp $short (branch: main, updated: "*" ago)" ]]
}

@test "shim: --version marks a dirty checkout" {
  local repo_dir short
  repo_dir=$(create_caller_repo "myapp")
  short=$(git -C "$repo_dir" rev-parse --short HEAD)
  touch "$repo_dir/uncommitted.txt"
  shiv_create_shim "myapp" "$repo_dir"

  run "$SHIV_BIN_DIR/myapp" --version
  [ "$status" -eq 0 ]
  [[ "$output" == "myapp $short* (branch: main, updated: "*" ago)" ]]
}

@test "shim: --version is handled before a named default task" {
  local repo_dir
  repo_dir=$(create_caller_repo "myapp")
  printf '#!/usr/bin/env bash\nprintf "NAMED_DEFAULT\\n"\n' > "$repo_dir/.mise/tasks/myapp"
  chmod +x "$repo_dir/.mise/tasks/myapp"
  git -C "$repo_dir" add .
  git -C "$repo_dir" commit -q -m "add default task"
  shiv_create_shim "myapp" "$repo_dir"

  run "$SHIV_BIN_DIR/myapp" --version
  [ "$status" -eq 0 ]
  [[ "$output" == "myapp "*" (branch: main, updated: "*" ago)" ]]
  [[ "$output" != *"NAMED_DEFAULT"* ]]
}

@test "shim: --version reports unknown metadata outside Git" {
  local repo_dir="$TEST_HOME/repos/myapp"
  mkdir -p "$repo_dir"
  shiv_create_shim "myapp" "$repo_dir"

  run "$SHIV_BIN_DIR/myapp" --version
  [ "$status" -eq 0 ]
  [ "$output" = "myapp unknown (branch: unknown, updated: unknown)" ]
}

@test "shim: --version does not inherit Git metadata from a parent checkout" {
  local parent_dir="$TEST_HOME/repos/parent" repo_dir="$TEST_HOME/repos/parent/myapp"
  mkdir -p "$parent_dir"
  git -C "$parent_dir" init -q -b unrelated
  git -C "$parent_dir" config user.email "test@test.com"
  git -C "$parent_dir" config user.name "Test"
  touch "$parent_dir/tracked"
  git -C "$parent_dir" add tracked
  git -C "$parent_dir" commit -q -m "init"
  mkdir -p "$repo_dir"
  shiv_create_shim "myapp" "$repo_dir"

  run "$SHIV_BIN_DIR/myapp" --version
  [ "$status" -eq 0 ]
  [ "$output" = "myapp unknown (branch: unknown, updated: unknown)" ]
}

@test "shim: --version ignores inherited Git repository environment" {
  local parent_dir="$TEST_HOME/repos/parent" repo_dir short
  repo_dir=$(create_caller_repo "myapp")
  short=$(git -C "$repo_dir" rev-parse --short HEAD)
  mkdir -p "$parent_dir"
  git -C "$parent_dir" init -q -b unrelated
  git -C "$parent_dir" config user.email "test@test.com"
  git -C "$parent_dir" config user.name "Test"
  touch "$parent_dir/tracked"
  git -C "$parent_dir" add tracked
  git -C "$parent_dir" commit -q -m "init"
  shiv_create_shim "myapp" "$repo_dir"

  run env GIT_DIR="$parent_dir/.git" "$SHIV_BIN_DIR/myapp" --version
  [ "$status" -eq 0 ]
  [[ "$output" == "myapp $short (branch: main, updated: "*" ago)" ]]
}
