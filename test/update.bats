#!/usr/bin/env bats
# shiv update test suite

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
  local tmp_dir="$TEST_HOME/tmp-clone"

  git clone -q "$bare_dir" "$tmp_dir"
  git -C "$tmp_dir" config user.email "test@test.com"
  git -C "$tmp_dir" config user.name "Test"
  echo "update" >> "$tmp_dir/README.md"
  git -C "$tmp_dir" add .
  git -C "$tmp_dir" commit -q -m "upstream update"
  git -C "$tmp_dir" push -q
  rm -rf "$tmp_dir"
}

# Helper: push a release tag to the remote.
push_remote_tag() {
  local name="$1" tag="$2"
  local bare_dir="$TEST_HOME/remotes/$name.git"
  local tmp_dir="$TEST_HOME/tmp-tag"

  git clone -q "$bare_dir" "$tmp_dir"
  git -C "$tmp_dir" config user.email "test@test.com"
  git -C "$tmp_dir" config user.name "Test"
  echo "$tag" > "$tmp_dir/$tag.txt"
  git -C "$tmp_dir" add .
  git -C "$tmp_dir" commit -q -m "$tag"
  git -C "$tmp_dir" tag -a "$tag" -m "$tag"
  git -C "$tmp_dir" push -q origin main "$tag"
  rm -rf "$tmp_dir"
}

# Helper: register a package as an explicit branch-tracking install.
register_branch_package() {
  local name="$1"
  shift
  local repo="$SHIV_PACKAGES_DIR/$name"
  local branch
  branch=$(git -C "$repo" rev-parse --abbrev-ref HEAD)
  SHIV_REF="$branch" SHIV_REF_MODE="branch" shiv_register "$name" "$repo" "$@"
}

# Helper: run shiv update through the mock shim
run_update() {
  local name="${1:-}"
  local cmd=(shiv update)
  [ -n "$name" ] && cmd+=("$name")
  "${cmd[@]}"
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
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "not a registered package or alias"
}

@test "update: missing repo directory shows error" {
  shiv_register "gone" "$TEST_HOME/nonexistent-repo"
  run run_update "gone"
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "repo not found"
}

# ============================================================================
# Successful update (no changes)
# ============================================================================

@test "update: up-to-date package shows ✓" {
  create_test_repo_with_remote "alpha"
  register_branch_package "alpha"
  shiv_create_shim "alpha" "$SHIV_PACKAGES_DIR/alpha"

  run run_update "alpha"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "✓ alpha"
  echo "$output" | grep -q "already up to date"
}

# ============================================================================
# Successful update (with new commits)
# ============================================================================

@test "update: release channel advances to newest release tag" {
  create_test_repo_with_remote "alpha"
  push_remote_tag "alpha" "v1.0.0"
  git -C "$SHIV_PACKAGES_DIR/alpha" fetch -q --tags origin
  git -C "$SHIV_PACKAGES_DIR/alpha" checkout -q "v1.0.0"
  SHIV_REF="v1.0.0" SHIV_REF_MODE="release" shiv_register "alpha" "$SHIV_PACKAGES_DIR/alpha"
  shiv_create_shim "alpha" "$SHIV_PACKAGES_DIR/alpha"

  push_remote_tag "alpha" "v1.1.0"

  run run_update "alpha"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "v1.0.0 → v1.1.0"
  [ "$(shiv_registry_ref "alpha")" = "v1.1.0" ]
  [ "$(shiv_registry_ref_mode "alpha")" = "release" ]
  [ "$(git -C "$SHIV_PACKAGES_DIR/alpha" describe --tags --exact-match HEAD)" = "v1.1.0" ]
}

@test "update: exact tag pin stays fixed when newer release exists" {
  create_test_repo_with_remote "alpha"
  push_remote_tag "alpha" "v1.0.0"
  git -C "$SHIV_PACKAGES_DIR/alpha" fetch -q --tags origin
  git -C "$SHIV_PACKAGES_DIR/alpha" checkout -q "v1.0.0"
  SHIV_REF="v1.0.0" SHIV_REF_MODE="tag" shiv_register "alpha" "$SHIV_PACKAGES_DIR/alpha"
  shiv_create_shim "alpha" "$SHIV_PACKAGES_DIR/alpha"

  push_remote_tag "alpha" "v1.1.0"

  run run_update "alpha"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "pinned to v1.0.0"
  [ "$(shiv_registry_ref "alpha")" = "v1.0.0" ]
  [ "$(shiv_registry_ref_mode "alpha")" = "tag" ]
  [ "$(git -C "$SHIV_PACKAGES_DIR/alpha" describe --tags --exact-match HEAD)" = "v1.0.0" ]
}

@test "update: legacy package without update intent fails with reinstall guidance" {
  create_test_repo_with_remote "alpha"
  shiv_register "alpha" "$SHIV_PACKAGES_DIR/alpha"

  run run_update "alpha"
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "legacy install has no update intent"
  echo "$output" | grep -q "shiv install alpha@latest"
  echo "$output" | grep -q "shiv install alpha@main"
}

@test "update: new commits shows commit range" {
  create_test_repo_with_remote "alpha"
  register_branch_package "alpha"
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
  register_branch_package "alpha"
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
  register_branch_package "alpha"
  shiv_create_shim "alpha" "$SHIV_PACKAGES_DIR/alpha"

  # Record shim content hash
  local before_hash
  before_hash=$(shasum "$SHIV_BIN_DIR/alpha" | cut -d' ' -f1)

  # Push a commit to remote and diverge locally
  push_remote_commit "alpha"
  git -C "$SHIV_PACKAGES_DIR/alpha" config user.email "test@test.com"
  git -C "$SHIV_PACKAGES_DIR/alpha" config user.name "Test"
  echo "local" > "$SHIV_PACKAGES_DIR/alpha/local.txt"
  git -C "$SHIV_PACKAGES_DIR/alpha" add .
  git -C "$SHIV_PACKAGES_DIR/alpha" commit -q -m "diverge"

  run run_update "alpha"

  local after_hash
  after_hash=$(shasum "$SHIV_BIN_DIR/alpha" | cut -d' ' -f1)
  [ "$before_hash" = "$after_hash" ]
}

# ============================================================================
# Summary table (multi-package)
# ============================================================================

@test "update: multi-package shows summary table" {
  create_test_repo_with_remote "alpha"
  create_test_repo_with_remote "bravo"
  register_branch_package "alpha"
  register_branch_package "bravo"
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
  register_branch_package "alpha"
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
  register_branch_package "alpha"
  shiv_create_shim "alpha" "$SHIV_PACKAGES_DIR/alpha"

  # Need a second package to trigger summary table
  create_test_repo_with_remote "bravo"
  register_branch_package "bravo"
  shiv_create_shim "bravo" "$SHIV_PACKAGES_DIR/bravo"

  run run_update
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "develop"
}

@test "update: shows dirty marker in summary table" {
  create_test_repo_with_remote "alpha"
  register_branch_package "alpha"
  shiv_create_shim "alpha" "$SHIV_PACKAGES_DIR/alpha"

  # Make it dirty
  touch "$SHIV_PACKAGES_DIR/alpha/uncommitted.txt"

  # Need a second package to trigger summary table
  create_test_repo_with_remote "bravo"
  register_branch_package "bravo"
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
  register_branch_package "alpha" "a"
  shiv_create_shim "alpha" "$SHIV_PACKAGES_DIR/alpha"

  run run_update "a"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "✓ alpha"
}
