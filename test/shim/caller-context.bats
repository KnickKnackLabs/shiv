#!/usr/bin/env bats

load helpers

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

  grep -q "SHIV_CALLER_PWD_VAR='MY_TOOL_CALLER_PWD'" "$SHIV_BIN_DIR/my-tool"
  run bash -c "cd /tmp && '$SHIV_BIN_DIR/my-tool' show-caller"
  [ "$status" -eq 0 ]
  [[ "$output" == *"/tmp"* ]]
}
