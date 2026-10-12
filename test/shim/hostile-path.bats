#!/usr/bin/env bats

load helpers

@test "shim: preserves literal package path characters without execution" {
  local hostile_root="$TEST_HOME/repos/path with space and apostrophe' and \$cash and \`tick\`"
  local repo_dir="$hostile_root/package"
  local shim_bin="$hostile_root/bin"
  local shim_cache="$hostile_root/cache"
  local mock_bin="$TEST_HOME/mock-bin"
  local marker="$TEST_HOME/tick-ran"

  mkdir -p "$repo_dir/.mise/tasks/deep" "$mock_bin"
  printf '[tools]\n' > "$repo_dir/mise.toml"
  cat > "$repo_dir/.mise/tasks/deep/path" <<'TASK'
#!/usr/bin/env bash
#MISE description="Prove literal package path execution"
printf 'HOSTILE_PATH_OK\n'
TASK
  chmod +x "$repo_dir/.mise/tasks/deep/path"
  mise trust "$repo_dir/mise.toml" 2>/dev/null

  cat > "$mock_bin/tick" <<'MOCK'
#!/usr/bin/env bash
: > "$SHIV_TICK_MARKER"
MOCK
  chmod +x "$mock_bin/tick"
  export PATH="$mock_bin:$PATH"
  export SHIV_TICK_MARKER="$marker"
  export cash="expanded"

  SHIV_BIN_DIR="$shim_bin" SHIV_CACHE_DIR="$shim_cache" \
    shiv_create_shim "hostile-tool" "$repo_dir"
  mkdir -p "$shim_cache/tasks"
  printf 'deep path\n' > "$shim_cache/tasks/hostile-tool"

  run bash -n "$shim_bin/hostile-tool"
  [ "$status" -eq 0 ]

  run "$shim_bin/hostile-tool" deep path
  [ ! -e "$marker" ]
  [ "$status" -eq 0 ]
  [[ "$output" == *"HOSTILE_PATH_OK"* ]]
}
