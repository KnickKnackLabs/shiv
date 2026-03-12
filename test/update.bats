#!/usr/bin/env bats
# shiv update test suite

REPO_DIR="$BATS_TEST_DIRNAME/.."
UPDATE_TASK="$REPO_DIR/.mise/tasks/update"

setup() {
  source "$REPO_DIR/lib/shim.sh"

  export TEST_HOME="$BATS_TMPDIR/shiv-test-$$"
  mkdir -p "$TEST_HOME"

  export SHIV_BIN_DIR="$TEST_HOME/.local/bin"
  export SHIV_DATA_DIR="$TEST_HOME/.local/share/shiv"
  export SHIV_PACKAGES_DIR="$SHIV_DATA_DIR/packages"
  export SHIV_CONFIG_DIR="$TEST_HOME/.config/shiv"
  export SHIV_CACHE_DIR="$TEST_HOME/.cache/shiv"
  export SHIV_REGISTRY="$SHIV_CONFIG_DIR/registry.json"

  mkdir -p "$SHIV_BIN_DIR"
  shiv_init_registry
}

teardown() {
  rm -rf "$TEST_HOME"
}

# Helper: create a git repo with a remote (bare repo as origin)
create_test_repo_with_remote() {
  local name="$1"
  local branch="${2:-main}"
  local repo_dir="$SHIV_PACKAGES_DIR/$name"
  local bare_dir="$TEST_HOME/remotes/$name.git"

  # Create a bare repo to act as remote
  mkdir -p "$bare_dir"
  git -C "$bare_dir" init -q --bare -b "$branch"

  # Create the working repo
  mkdir -p "$repo_dir"
  git -C "$repo_dir" init -q -b "$branch"
  git -C "$repo_dir" config user.email "test@test.com"
  git -C "$repo_dir" config user.name "Test"
  touch "$repo_dir/README.md"
  git -C "$repo_dir" add .
  git -C "$repo_dir" commit -q -m "init"
  git -C "$repo_dir" remote add origin "$bare_dir"
  git -C "$repo_dir" push -q -u origin "$branch"
}

# Helper: push a new commit to the remote (simulates upstream activity)
push_remote_commit() {
  local name="$1"
  local bare_dir="$TEST_HOME/remotes/$name.git"
  local tmp_dir="$TEST_HOME/tmp-clone-$$"

  git clone -q "$bare_dir" "$tmp_dir"
  git -C "$tmp_dir" config user.email "test@test.com"
  git -C "$tmp_dir" config user.name "Test"
  echo "update" >> "$tmp_dir/README.md"
  git -C "$tmp_dir" add .
  git -C "$tmp_dir" commit -q -m "upstream update"
  git -C "$tmp_dir" push -q
  rm -rf "$tmp_dir"
}

# Helper: run the update task
run_update() {
  local name="${1:-}"
  usage_name="$name" bash "$UPDATE_TASK"
}

# Helper: extract package names from gum table output
extract_packages() {
  grep '│' | grep -v 'PACKAGE' | sed 's/│/|/g' | awk -F'|' '{gsub(/^ +| +$/, "", $2); print $2}'
}

# Helper: extract a column from gum table output by position (1-indexed, after border)
extract_column() {
  local col="$1"
  grep '│' | grep -v 'PACKAGE' | sed 's/│/|/g' | awk -F'|' -v c="$((col + 1))" '{gsub(/^ +| +$/, "", $c); print $c}'
}

# ============================================================================
# Empty / missing
# ============================================================================

@test "update: empty registry shows message" {
  run run_update
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "No tools registered"
}

@test "update: unknown package shows error" {
  run run_update "nonexistent"
  echo "$output" | grep -q "not a registered package or alias"
}

@test "update: missing repo directory shows error" {
  shiv_register "gone" "/tmp/nonexistent-repo-$$"
  run run_update "gone"
  echo "$output" | grep -q "repo not found"
}

# ============================================================================
# Successful update (no changes)
# ============================================================================

@test "update: up-to-date package shows ✓" {
  create_test_repo_with_remote "alpha"
  shiv_register "alpha" "$SHIV_PACKAGES_DIR/alpha"
  shiv_create_shim "alpha" "$SHIV_PACKAGES_DIR/alpha"

  run run_update "alpha"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "✓ alpha"
  echo "$output" | grep -q "already up to date"
}

# ============================================================================
# Successful update (with new commits)
# ============================================================================

@test "update: new commits shows commit range" {
  create_test_repo_with_remote "alpha"
  shiv_register "alpha" "$SHIV_PACKAGES_DIR/alpha"
  shiv_create_shim "alpha" "$SHIV_PACKAGES_DIR/alpha"

  push_remote_commit "alpha"

  run run_update "alpha"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "✓ alpha"
  # Should show "hash1 → hash2 (1 commits)"
  echo "$output" | grep -qE '[0-9a-f]+ → [0-9a-f]+'
}

# ============================================================================
# Pull failure
# ============================================================================

@test "update: diverged repo shows ⚠ with reason" {
  create_test_repo_with_remote "alpha"
  shiv_register "alpha" "$SHIV_PACKAGES_DIR/alpha"
  shiv_create_shim "alpha" "$SHIV_PACKAGES_DIR/alpha"

  # Push a commit to remote
  push_remote_commit "alpha"

  # Make a local commit that diverges
  git -C "$SHIV_PACKAGES_DIR/alpha" config user.email "test@test.com"
  git -C "$SHIV_PACKAGES_DIR/alpha" config user.name "Test"
  echo "local change" > "$SHIV_PACKAGES_DIR/alpha/local.txt"
  git -C "$SHIV_PACKAGES_DIR/alpha" add .
  git -C "$SHIV_PACKAGES_DIR/alpha" commit -q -m "local divergence"

  run run_update "alpha"
  echo "$output" | grep -q "⚠ alpha"
  echo "$output" | grep -qi "fast-forward"
}

@test "update: pull failure does not refresh shim" {
  create_test_repo_with_remote "alpha"
  shiv_register "alpha" "$SHIV_PACKAGES_DIR/alpha"
  shiv_create_shim "alpha" "$SHIV_PACKAGES_DIR/alpha"

  # Record shim modification time
  local before_mtime
  before_mtime=$(stat -f %m "$SHIV_BIN_DIR/alpha")

  # Push a commit to remote and diverge locally
  push_remote_commit "alpha"
  git -C "$SHIV_PACKAGES_DIR/alpha" config user.email "test@test.com"
  git -C "$SHIV_PACKAGES_DIR/alpha" config user.name "Test"
  echo "local" > "$SHIV_PACKAGES_DIR/alpha/local.txt"
  git -C "$SHIV_PACKAGES_DIR/alpha" add .
  git -C "$SHIV_PACKAGES_DIR/alpha" commit -q -m "diverge"

  # Small delay so mtime would differ if shim were touched
  sleep 1

  run run_update "alpha"

  local after_mtime
  after_mtime=$(stat -f %m "$SHIV_BIN_DIR/alpha")
  [ "$before_mtime" = "$after_mtime" ]
}

# ============================================================================
# Summary table (multi-package)
# ============================================================================

@test "update: multi-package shows summary table" {
  create_test_repo_with_remote "alpha"
  create_test_repo_with_remote "bravo"
  shiv_register "alpha" "$SHIV_PACKAGES_DIR/alpha"
  shiv_register "bravo" "$SHIV_PACKAGES_DIR/bravo"
  shiv_create_shim "alpha" "$SHIV_PACKAGES_DIR/alpha"
  shiv_create_shim "bravo" "$SHIV_PACKAGES_DIR/bravo"

  run run_update
  [ "$status" -eq 0 ]
  # Should contain gum table borders
  echo "$output" | grep -q '┌'
  echo "$output" | grep -q 'PACKAGE'
}

@test "update: single package skips summary table" {
  create_test_repo_with_remote "alpha"
  shiv_register "alpha" "$SHIV_PACKAGES_DIR/alpha"
  shiv_create_shim "alpha" "$SHIV_PACKAGES_DIR/alpha"

  run run_update "alpha"
  [ "$status" -eq 0 ]
  # Should NOT contain table borders
  ! echo "$output" | grep -q '┌'
}

# ============================================================================
# Git metadata in output
# ============================================================================

@test "update: shows branch in summary table" {
  create_test_repo_with_remote "alpha" "develop"
  shiv_register "alpha" "$SHIV_PACKAGES_DIR/alpha"
  shiv_create_shim "alpha" "$SHIV_PACKAGES_DIR/alpha"

  # Need a second package to trigger summary table
  create_test_repo_with_remote "bravo"
  shiv_register "bravo" "$SHIV_PACKAGES_DIR/bravo"
  shiv_create_shim "bravo" "$SHIV_PACKAGES_DIR/bravo"

  run run_update
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "develop"
}

@test "update: shows dirty marker in summary table" {
  create_test_repo_with_remote "alpha"
  shiv_register "alpha" "$SHIV_PACKAGES_DIR/alpha"
  shiv_create_shim "alpha" "$SHIV_PACKAGES_DIR/alpha"

  # Make it dirty
  touch "$SHIV_PACKAGES_DIR/alpha/uncommitted.txt"

  # Need a second package to trigger summary table
  create_test_repo_with_remote "bravo"
  shiv_register "bravo" "$SHIV_PACKAGES_DIR/bravo"
  shiv_create_shim "bravo" "$SHIV_PACKAGES_DIR/bravo"

  run run_update
  [ "$status" -eq 0 ]
  # The alpha row should have a * in the VERSION column
  echo "$output" | grep "alpha" | grep -q '\*'
}

# ============================================================================
# Alias resolution
# ============================================================================

@test "update: resolves alias to package name" {
  create_test_repo_with_remote "alpha"
  shiv_register "alpha" "$SHIV_PACKAGES_DIR/alpha" "a"
  shiv_create_shim "alpha" "$SHIV_PACKAGES_DIR/alpha"

  run run_update "a"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "✓ alpha"
}
