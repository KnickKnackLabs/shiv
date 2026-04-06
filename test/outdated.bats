#!/usr/bin/env bats
# shiv outdated test suite

REPO_DIR="$BATS_TEST_DIRNAME/.."
load helpers

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

  # Bare repo dir for simulating remotes
  export REMOTES_DIR="$TEST_HOME/remotes"
  mkdir -p "$REMOTES_DIR"

  shiv_init_registry
  setup_shiv_on_path
}

teardown() {
  rm -rf "$TEST_HOME"
}

# Helper: create a bare remote repo with tags
# Usage: create_remote <name> [tag1 tag2 ...]
create_remote() {
  local name="$1"; shift
  local remote_dir="$REMOTES_DIR/$name.git"

  # Create a temporary working repo to build history
  local work_dir="$TEST_HOME/work-$name"
  mkdir -p "$work_dir"
  git -C "$work_dir" init -q -b main
  git -C "$work_dir" config user.email "test@test.com"
  git -C "$work_dir" config user.name "Test"
  touch "$work_dir/README.md"
  git -C "$work_dir" add .
  git -C "$work_dir" commit -q -m "init"

  # Create tags
  for tag in "$@"; do
    touch "$work_dir/$tag"
    git -C "$work_dir" add .
    git -C "$work_dir" commit -q -m "$tag"
    git -C "$work_dir" tag -a "$tag" -m "$tag"
  done

  # Clone to bare repo (acts as remote)
  git clone -q --bare "$work_dir" "$remote_dir"
  rm -rf "$work_dir"

  echo "$remote_dir"
}

# Helper: clone from a remote and register
# Usage: create_package_from_remote <name> <remote_dir> [checkout_ref]
create_package_from_remote() {
  local name="$1" remote_dir="$2" ref="${3:-}"
  local pkg_dir="$SHIV_PACKAGES_DIR/$name"

  git clone -q "$remote_dir" "$pkg_dir"
  git -C "$pkg_dir" config user.email "test@test.com"
  git -C "$pkg_dir" config user.name "Test"

  if [ -n "$ref" ]; then
    git -C "$pkg_dir" checkout -q "$ref"
  fi

  shiv_register "$name" "$pkg_dir"
}

# Helper: create a standalone package (no remote)
create_local_package() {
  local name="$1"
  local pkg_dir="$SHIV_PACKAGES_DIR/$name"

  mkdir -p "$pkg_dir"
  git -C "$pkg_dir" init -q -b main
  git -C "$pkg_dir" config user.email "test@test.com"
  git -C "$pkg_dir" config user.name "Test"
  touch "$pkg_dir/README.md"
  git -C "$pkg_dir" add .
  git -C "$pkg_dir" commit -q -m "init"

  # Remove origin so there's no remote
  git -C "$pkg_dir" remote remove origin 2>/dev/null || true

  shiv_register "$name" "$pkg_dir"
}

# ============================================================================
# Empty / no packages
# ============================================================================

@test "outdated: empty registry shows help message" {
  run shiv outdated
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "No packages registered"
}

# ============================================================================
# Up to date (on latest tag)
# ============================================================================

@test "outdated: package on latest tag shows up to date" {
  remote_dir=$(create_remote "alpha" "v1.0.0" "v1.1.0")
  create_package_from_remote "alpha" "$remote_dir" "v1.1.0"

  run shiv outdated
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "alpha"
  echo "$output" | grep -q "v1.1.0"
  echo "$output" | grep -q "✓ up to date"
}

# ============================================================================
# Outdated (pinned to old tag)
# ============================================================================

@test "outdated: package on old tag shows outdated" {
  remote_dir=$(create_remote "alpha" "v1.0.0" "v2.0.0")
  create_package_from_remote "alpha" "$remote_dir" "v1.0.0"

  run shiv outdated
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "alpha"
  echo "$output" | grep -q "v1.0.0"
  echo "$output" | grep -q "v2.0.0"
  echo "$output" | grep -q "⚠ outdated"
}

# ============================================================================
# On branch, newer tag available
# ============================================================================

@test "outdated: on branch with newer remote tag shows newer tag available" {
  remote_dir=$(create_remote "alpha" "v1.0.0" "v2.0.0")
  create_package_from_remote "alpha" "$remote_dir"

  # We're on main (not a tag), but v2.0.0 exists locally too (cloned all tags)
  # Reset to before v2.0.0 to simulate not having the latest tag locally
  git -C "$SHIV_PACKAGES_DIR/alpha" tag -d "v2.0.0" 2>/dev/null

  run shiv outdated
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "alpha"
  echo "$output" | grep -q "⚠ newer tag available"
}

@test "outdated: on branch with latest tag present locally shows ok" {
  remote_dir=$(create_remote "alpha" "v1.0.0")
  create_package_from_remote "alpha" "$remote_dir"

  # Add a local commit beyond the tag so HEAD isn't on the tag itself
  touch "$SHIV_PACKAGES_DIR/alpha/extra"
  git -C "$SHIV_PACKAGES_DIR/alpha" add .
  git -C "$SHIV_PACKAGES_DIR/alpha" commit -q -m "local work"

  run shiv outdated
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "alpha"
  echo "$output" | grep -q "✓ latest tag present"
}

# ============================================================================
# No remote
# ============================================================================

@test "outdated: package with no remote shows no remote" {
  create_local_package "alpha"

  run shiv outdated
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "alpha"
  echo "$output" | grep -q "· no remote"
}

# ============================================================================
# Not registered
# ============================================================================

@test "outdated: unknown package shows not registered" {
  run shiv outdated bogus
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "bogus"
  echo "$output" | grep -q "✗ not registered"
}

# ============================================================================
# Positional args filter
# ============================================================================

@test "outdated: positional args filter to specific packages" {
  remote_dir_a=$(create_remote "alpha" "v1.0.0")
  remote_dir_b=$(create_remote "bravo" "v1.0.0")
  create_package_from_remote "alpha" "$remote_dir_a" "v1.0.0"
  create_package_from_remote "bravo" "$remote_dir_b" "v1.0.0"

  run shiv outdated alpha
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "alpha"
  ! echo "$output" | grep -q "bravo"
}

@test "outdated: multiple positional args check multiple packages" {
  remote_dir_a=$(create_remote "alpha" "v1.0.0")
  remote_dir_b=$(create_remote "bravo" "v1.0.0")
  remote_dir_c=$(create_remote "charlie" "v1.0.0")
  create_package_from_remote "alpha" "$remote_dir_a" "v1.0.0"
  create_package_from_remote "bravo" "$remote_dir_b" "v1.0.0"
  create_package_from_remote "charlie" "$remote_dir_c" "v1.0.0"

  run shiv outdated alpha charlie
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "alpha"
  echo "$output" | grep -q "charlie"
  ! echo "$output" | grep -q "bravo"
}

# ============================================================================
# No tags on remote (compare HEAD)
# ============================================================================

@test "outdated: no remote tags, same HEAD shows up to date" {
  remote_dir=$(create_remote "alpha")
  create_package_from_remote "alpha" "$remote_dir"

  run shiv outdated
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "alpha"
  echo "$output" | grep -q "✓ up to date"
}

@test "outdated: no remote tags, different HEAD shows behind remote" {
  remote_dir=$(create_remote "alpha")
  create_package_from_remote "alpha" "$remote_dir"

  # Push a new commit to the remote
  local work_dir="$TEST_HOME/work-push"
  git clone -q "$remote_dir" "$work_dir"
  git -C "$work_dir" config user.email "test@test.com"
  git -C "$work_dir" config user.name "Test"
  touch "$work_dir/new-file"
  git -C "$work_dir" add .
  git -C "$work_dir" commit -q -m "new commit"
  git -C "$work_dir" push -q origin main

  run shiv outdated
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "alpha"
  echo "$output" | grep -q "⚠ behind remote"
}

# ============================================================================
# Semver sorting
# ============================================================================

@test "outdated: correctly identifies latest among many semver tags" {
  remote_dir=$(create_remote "alpha" "v0.1.0" "v0.2.0" "v0.10.0" "v1.0.0" "v1.2.0" "v1.10.0")
  create_package_from_remote "alpha" "$remote_dir" "v1.2.0"

  run shiv outdated
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "v1.10.0"
  echo "$output" | grep -q "⚠ outdated"
}

@test "outdated: v-prefixed tags with major version > 9 sort correctly" {
  remote_dir=$(create_remote "alpha" "v1.0.0" "v2.0.0" "v10.0.0")
  create_package_from_remote "alpha" "$remote_dir" "v2.0.0"

  run shiv outdated
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "v10.0.0"
  echo "$output" | grep -q "⚠ outdated"
}

# ============================================================================
# Exit codes
# ============================================================================

@test "outdated: exits 0 when all packages are current" {
  remote_dir=$(create_remote "alpha" "v1.0.0")
  create_package_from_remote "alpha" "$remote_dir" "v1.0.0"

  run shiv outdated
  [ "$status" -eq 0 ]
}

@test "outdated: exits 1 when any package is outdated" {
  remote_dir_a=$(create_remote "alpha" "v1.0.0")
  remote_dir_b=$(create_remote "bravo" "v1.0.0" "v2.0.0")
  create_package_from_remote "alpha" "$remote_dir_a" "v1.0.0"
  create_package_from_remote "bravo" "$remote_dir_b" "v1.0.0"

  run shiv outdated
  [ "$status" -eq 1 ]
  echo "$output" | grep "alpha" | grep -q "✓ up to date"
  echo "$output" | grep "bravo" | grep -q "⚠ outdated"
}

# ============================================================================
# Non-git / missing repo
# ============================================================================

@test "outdated: non-git directory shows not a git repo" {
  local pkg_dir="$SHIV_PACKAGES_DIR/alpha"
  mkdir -p "$pkg_dir"
  shiv_register "alpha" "$pkg_dir"

  run shiv outdated
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "· not a git repo"
}

@test "outdated: missing repo shows repo missing" {
  shiv_register "ghost" "/tmp/nonexistent-shiv-test-$$"

  run shiv outdated
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "✗ repo missing"
}
