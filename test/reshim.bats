#!/usr/bin/env bats
# shiv reshim test suite

REPO_DIR="$BATS_TEST_DIRNAME/.."
load helpers

setup() {
  source "$REPO_DIR/lib/shim.sh"

  export TEST_HOME="$BATS_TEST_TMPDIR/shiv"
  export SHIV_BIN_DIR="$TEST_HOME/.local/bin"
  export SHIV_DATA_DIR="$TEST_HOME/.local/share/shiv"
  export SHIV_PACKAGES_DIR="$SHIV_DATA_DIR/packages"
  export SHIV_CONFIG_DIR="$TEST_HOME/.config/shiv"
  export SHIV_CACHE_DIR="$TEST_HOME/.cache/shiv"
  export SHIV_REGISTRY="$SHIV_CONFIG_DIR/registry.json"
  export SHIV_SKIP_CACHE=1

  mkdir -p "$SHIV_BIN_DIR"
  shiv_init_registry
  setup_shiv_on_path
}

create_package_repo() {
  local name="$1"
  local repo="$SHIV_PACKAGES_DIR/$name"

  mkdir -p "$repo"
  git -C "$repo" init -q -b main
  git -C "$repo" config user.email "test@test.com"
  git -C "$repo" config user.name "Test"
  printf '# %s\n' "$name" > "$repo/README.md"
  git -C "$repo" add README.md
  git -C "$repo" commit -q -m "init"
}

register_package() {
  local name="$1" mode="$2" ref="$3"
  shift 3
  local repo="$SHIV_PACKAGES_DIR/$name"

  SHIV_REF="$ref" SHIV_REF_MODE="$mode" shiv_register "$name" "$repo" "$@"
}

run_reshim() {
  shiv reshim
}

@test "reshim: empty registry shows message" {
  run run_reshim

  [ "$status" -eq 0 ]
  [[ "$output" == *"No tools registered."* ]]
}

@test "reshim: invalid registry entries fail instead of disappearing" {
  printf '%s\n' '{"broken":"not-an-object"}' > "$SHIV_REGISTRY"

  run run_reshim

  [ "$status" -eq 1 ]
  [[ "$output" == *"could not read registered packages"* ]]
  [ ! -e "$SHIV_BIN_DIR/broken" ]
}

@test "reshim: refreshes exact, local, self, and alias artifacts without scanning package storage" {
  create_package_repo shiv
  git -C "$SHIV_PACKAGES_DIR/shiv" -c tag.gpgSign=false tag v1.0.0
  register_package shiv tag v1.0.0 shiv-next

  create_package_repo local-tool
  register_package local-tool local main

  local shiv_head local_head shiv_branch local_branch
  shiv_head=$(git -C "$SHIV_PACKAGES_DIR/shiv" rev-parse HEAD)
  local_head=$(git -C "$SHIV_PACKAGES_DIR/local-tool" rev-parse HEAD)
  shiv_branch=$(git -C "$SHIV_PACKAGES_DIR/shiv" branch --show-current)
  local_branch=$(git -C "$SHIV_PACKAGES_DIR/local-tool" branch --show-current)

  printf 'stale shiv\n' > "$SHIV_BIN_DIR/shiv"
  printf 'stale local\n' > "$SHIV_BIN_DIR/local-tool"

  mkdir -p "$SHIV_PACKAGES_DIR/inactive"
  printf 'do not touch\n' > "$SHIV_PACKAGES_DIR/inactive/sentinel"
  printf 'inactive shim\n' > "$SHIV_BIN_DIR/inactive"

  run run_reshim

  [ "$status" -eq 0 ]
  local reshim_output="$output"
  [ "$(git -C "$SHIV_PACKAGES_DIR/shiv" rev-parse HEAD)" = "$shiv_head" ]
  [ "$(git -C "$SHIV_PACKAGES_DIR/local-tool" rev-parse HEAD)" = "$local_head" ]
  [ "$(git -C "$SHIV_PACKAGES_DIR/shiv" branch --show-current)" = "$shiv_branch" ]
  [ "$(git -C "$SHIV_PACKAGES_DIR/local-tool" branch --show-current)" = "$local_branch" ]
  grep -q '^# managed by shiv$' "$SHIV_BIN_DIR/shiv"
  grep -q '^# managed by shiv$' "$SHIV_BIN_DIR/local-tool"
  [ "$(readlink "$SHIV_BIN_DIR/shiv-next")" = "shiv" ]
  [ "$(cat "$SHIV_PACKAGES_DIR/inactive/sentinel")" = "do not touch" ]
  [ "$(cat "$SHIV_BIN_DIR/inactive")" = "inactive shim" ]
  [[ "$reshim_output" == *"✓ shiv — shim and caches refreshed"* ]]
  [[ "$reshim_output" == *"✓ local-tool — shim and caches refreshed"* ]]
  [[ "$reshim_output" != *"inactive"* ]]

  run "$SHIV_BIN_DIR/shiv" --version
  [ "$status" -eq 0 ]
  [[ "$output" == *"shiv v1.0.0 (branch:"* ]]
}

@test "reshim: dirty package fails visibly before changing any generated artifact" {
  create_package_repo dirty-tool
  register_package dirty-tool local main dirty-alias

  mkdir -p "$SHIV_PACKAGES_DIR/dirty-tool/.mise/tasks"
  cat > "$SHIV_PACKAGES_DIR/dirty-tool/.mise/tasks/current" <<'TASK'
#!/usr/bin/env bash
#MISE description="Current task"
echo current
TASK
  chmod +x "$SHIV_PACKAGES_DIR/dirty-tool/.mise/tasks/current"
  git -C "$SHIV_PACKAGES_DIR/dirty-tool" add .mise/tasks/current
  git -C "$SHIV_PACKAGES_DIR/dirty-tool" commit -q -m "add task"
  unset SHIV_SKIP_CACHE

  printf 'old shim\n' > "$SHIV_BIN_DIR/dirty-tool"
  ln -s old-target "$SHIV_BIN_DIR/dirty-alias"
  mkdir -p "$SHIV_CACHE_DIR/completions" "$SHIV_CACHE_DIR/tasks"
  printf 'old completions\n' > "$SHIV_CACHE_DIR/completions/dirty-tool.cache"
  printf 'old task map\n' > "$SHIV_CACHE_DIR/tasks/dirty-tool"
  printf 'dirty\n' >> "$SHIV_PACKAGES_DIR/dirty-tool/README.md"

  run run_reshim

  [ "$status" -eq 1 ]
  [[ "$output" == *"dirty-tool — dirty worktree — skipped"* ]]
  [ "$(cat "$SHIV_BIN_DIR/dirty-tool")" = "old shim" ]
  [ "$(readlink "$SHIV_BIN_DIR/dirty-alias")" = "old-target" ]
  [ "$(cat "$SHIV_CACHE_DIR/completions/dirty-tool.cache")" = "old completions" ]
  [ "$(cat "$SHIV_CACHE_DIR/tasks/dirty-tool")" = "old task map" ]
}

@test "reshim: cache discovery failure is reported and preserves old caches" {
  create_package_repo broken-cache
  register_package broken-cache branch main

  mkdir -p "$SHIV_CACHE_DIR/completions" "$SHIV_CACHE_DIR/tasks"
  printf 'old completions\n' > "$SHIV_CACHE_DIR/completions/broken-cache.cache"
  printf 'old task map\n' > "$SHIV_CACHE_DIR/tasks/broken-cache"
  printf '[invalid\n' > "$SHIV_PACKAGES_DIR/broken-cache/mise.toml"
  git -C "$SHIV_PACKAGES_DIR/broken-cache" add mise.toml
  git -C "$SHIV_PACKAGES_DIR/broken-cache" commit -q -m "add invalid mise config"
  unset SHIV_SKIP_CACHE

  run run_reshim

  [ "$status" -eq 1 ]
  [[ "$output" == *"broken-cache — failed to refresh generated artifacts"* ]]
  [ "$(cat "$SHIV_CACHE_DIR/completions/broken-cache.cache")" = "old completions" ]
  [ "$(cat "$SHIV_CACHE_DIR/tasks/broken-cache")" = "old task map" ]
}

@test "reshim: missing and invalid repos fail while clean registered packages continue" {
  create_package_repo clean-tool
  register_package clean-tool branch main
  SHIV_REF=main SHIV_REF_MODE=branch \
    shiv_register missing-tool "$SHIV_PACKAGES_DIR/missing-tool"
  mkdir -p "$SHIV_PACKAGES_DIR/not-git"
  SHIV_REF=main SHIV_REF_MODE=local \
    shiv_register invalid-tool "$SHIV_PACKAGES_DIR/not-git"

  printf 'stale clean\n' > "$SHIV_BIN_DIR/clean-tool"

  run run_reshim

  [ "$status" -eq 1 ]
  grep -q '^# managed by shiv$' "$SHIV_BIN_DIR/clean-tool"
  [[ "$output" == *"✓ clean-tool — shim and caches refreshed"* ]]
  [[ "$output" == *"✗ missing-tool — repo not found"* ]]
  [[ "$output" == *"✗ invalid-tool — not a Git worktree"* ]]
}

@test "reshim: refreshes completion and task-map caches through the public command" {
  create_package_repo cached-tool
  register_package cached-tool branch main
  unset SHIV_SKIP_CACHE

  mkdir -p "$SHIV_PACKAGES_DIR/cached-tool/.mise/tasks"
  cat > "$SHIV_PACKAGES_DIR/cached-tool/.mise/tasks/hello" <<'TASK'
#!/usr/bin/env bash
#MISE description="Say hello"
echo hello
TASK
  chmod +x "$SHIV_PACKAGES_DIR/cached-tool/.mise/tasks/hello"
  git -C "$SHIV_PACKAGES_DIR/cached-tool" add .mise/tasks/hello
  git -C "$SHIV_PACKAGES_DIR/cached-tool" commit -q -m "add task"

  run run_reshim

  [ "$status" -eq 0 ]
  grep -q $'^hello\tSay hello$' "$SHIV_CACHE_DIR/completions/cached-tool.cache"
  grep -q '^hello$' "$SHIV_CACHE_DIR/tasks/cached-tool"

  rm "$SHIV_PACKAGES_DIR/cached-tool/.mise/tasks/hello"
  git -C "$SHIV_PACKAGES_DIR/cached-tool" add -u
  git -C "$SHIV_PACKAGES_DIR/cached-tool" commit -q -m "remove task"

  run run_reshim

  [ "$status" -eq 0 ]
  [ ! -e "$SHIV_CACHE_DIR/completions/cached-tool.cache" ]
  [ ! -e "$SHIV_CACHE_DIR/tasks/cached-tool" ]
}
