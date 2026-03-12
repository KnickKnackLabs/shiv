#!/usr/bin/env bats
# shiv doctor test suite

REPO_DIR="$BATS_TEST_DIRNAME/.."
DOCTOR_TASK="$REPO_DIR/.mise/tasks/doctor"

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

# Helper: create a minimal installed package (repo, shim, registry)
create_installed_package() {
  local name="$1"
  local repo_dir="$SHIV_PACKAGES_DIR/$name"

  mkdir -p "$repo_dir"
  git -C "$repo_dir" init -q -b main
  git -C "$repo_dir" config user.email "test@test.com"
  git -C "$repo_dir" config user.name "Test"
  touch "$repo_dir/README.md"
  git -C "$repo_dir" add .
  git -C "$repo_dir" commit -q -m "init"

  shift
  shiv_register "$name" "$repo_dir" "$@"
  shiv_create_shim "$name" "$repo_dir"

  # Create alias symlinks if provided
  local aliases=("$@")
  if [ ${#aliases[@]} -gt 0 ]; then
    shiv_create_alias_symlinks "$name" "${aliases[@]}"
  fi
}

# Helper: run the doctor task
run_doctor() {
  bash "$DOCTOR_TASK" 2>&1
}

# ============================================================================
# Header
# ============================================================================

@test "doctor: shows health header" {
  run run_doctor
  echo "$output" | grep -q "SHIV HEALTH"
  echo "$output" | grep -q "Registry"
  echo "$output" | grep -q "Bin dir"
}

@test "doctor: shows bin dir status" {
  run run_doctor
  echo "$output" | grep -q "$SHIV_BIN_DIR"
}

@test "doctor: detects missing bin dir" {
  rmdir "$SHIV_BIN_DIR"

  run run_doctor
  echo "$output" | grep -q "not found"
}

# ============================================================================
# Empty registry
# ============================================================================

@test "doctor: empty registry shows no tools message" {
  run run_doctor
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "No tools registered"
}

# ============================================================================
# Healthy packages
# ============================================================================

@test "doctor: healthy package shows ✓" {
  create_installed_package "alpha"

  run run_doctor
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "PACKAGE"
  echo "$output" | grep "alpha" | grep -q "✓"
}

@test "doctor: multiple healthy packages all show ✓" {
  create_installed_package "alpha"
  create_installed_package "bravo"

  run run_doctor
  [ "$status" -eq 0 ]
  echo "$output" | grep "alpha" | grep -q "✓"
  echo "$output" | grep "bravo" | grep -q "✓"
}

@test "doctor: exits 0 when all healthy" {
  create_installed_package "alpha"

  run run_doctor
  [ "$status" -eq 0 ]
}

# ============================================================================
# Missing repo
# ============================================================================

@test "doctor: missing repo shows ✗" {
  shiv_register "gone" "/tmp/nonexistent-repo-$$"
  shiv_create_shim "gone" "/tmp/nonexistent-repo-$$"

  run run_doctor
  [ "$status" -ne 0 ]
  echo "$output" | grep "gone" | grep -q "✗"
  echo "$output" | grep -q "repo not found"
}

# ============================================================================
# Missing shim
# ============================================================================

@test "doctor: missing shim shows ✗" {
  create_installed_package "alpha"
  rm "$SHIV_BIN_DIR/alpha"

  run run_doctor
  [ "$status" -ne 0 ]
  echo "$output" | grep "alpha" | grep -q "✗"
  echo "$output" | grep -q "shim missing"
}

# ============================================================================
# Shim not managed by shiv
# ============================================================================

@test "doctor: unmanaged shim shows ✗" {
  create_installed_package "alpha"
  # Overwrite shim with a non-shiv script
  echo '#!/bin/bash' > "$SHIV_BIN_DIR/alpha"

  run run_doctor
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "not managed by shiv"
}

# ============================================================================
# Shim points to wrong repo
# ============================================================================

@test "doctor: shim pointing to wrong repo shows ✗" {
  create_installed_package "alpha"
  # Change registry path without updating shim
  local other_dir="$SHIV_PACKAGES_DIR/other"
  mkdir -p "$other_dir"
  jq --arg name "alpha" --arg path "$other_dir" \
    '.[$name].path = $path' "$SHIV_REGISTRY" > "$SHIV_REGISTRY.tmp"
  mv "$SHIV_REGISTRY.tmp" "$SHIV_REGISTRY"

  run run_doctor
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "shim points to"
}

# ============================================================================
# Alias symlinks
# ============================================================================

@test "doctor: missing alias symlink shows ✗" {
  create_installed_package "alpha" "a"
  rm "$SHIV_BIN_DIR/a"

  run run_doctor
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "alias symlink missing"
}

@test "doctor: alias symlink wrong target shows ✗" {
  create_installed_package "alpha" "a"
  # Point alias at wrong target
  rm "$SHIV_BIN_DIR/a"
  ln -s "wrong" "$SHIV_BIN_DIR/a"

  run run_doctor
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "wrong target"
}

# ============================================================================
# Issue details
# ============================================================================

@test "doctor: shows issue count in table" {
  create_installed_package "alpha" "a" "al"
  rm "$SHIV_BIN_DIR/a"
  rm "$SHIV_BIN_DIR/al"

  run run_doctor
  [ "$status" -ne 0 ]
  # Should show ✗ (2) for two missing alias symlinks
  echo "$output" | grep "alpha" | grep -q "✗ (2)"
}

@test "doctor: shows issue details below table" {
  create_installed_package "alpha"
  rm "$SHIV_BIN_DIR/alpha"

  run run_doctor
  [ "$status" -ne 0 ]
  # Package name appears in the detail section (bold label)
  echo "$output" | grep -q "alpha"
  echo "$output" | grep -q "shim missing"
}

@test "doctor: healthy and broken packages together" {
  create_installed_package "alpha"
  create_installed_package "bravo"
  rm "$SHIV_BIN_DIR/bravo"

  run run_doctor
  [ "$status" -ne 0 ]
  echo "$output" | grep "alpha" | grep -q "✓"
  echo "$output" | grep "bravo" | grep -q "✗"
}
