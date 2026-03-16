#!/usr/bin/env bats
# shiv list test suite

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

  shiv_init_registry
  setup_shiv_on_path
}

teardown() {
  rm -rf "$TEST_HOME"
}

# Helper: create a git repo with a specific commit date
# Usage: create_test_repo <name> [iso_date] [branch]
create_test_repo() {
  local name="$1"
  local date="${2:-2024-06-01T00:00:00+00:00}"
  local branch="${3:-main}"
  local repo_dir="$SHIV_PACKAGES_DIR/$name"

  mkdir -p "$repo_dir"
  git -C "$repo_dir" init -q -b "$branch"
  git -C "$repo_dir" config user.email "test@test.com"
  git -C "$repo_dir" config user.name "Test"
  touch "$repo_dir/README.md"
  git -C "$repo_dir" add .
  GIT_COMMITTER_DATE="$date" \
    git -C "$repo_dir" commit -q -m "init" --date "$date"
}

# Helper: run shiv list through the mock shim
# Usage: run_list [--sort field] [--asc|--desc]
run_list() {
  local cmd=(shiv list)
  while [ $# -gt 0 ]; do
    case "$1" in
      --sort) cmd+=(--sort "$2"); shift 2 ;;
      --asc) cmd+=(--asc); shift ;;
      --desc) cmd+=(--desc); shift ;;
      *) shift ;;
    esac
  done
  "${cmd[@]}"
}

# Extract package names from gum table output (skip header and border lines)
extract_packages() {
  grep '│' | grep -v 'PACKAGE' | sed 's/│/|/g' | awk -F'|' '{gsub(/^ +| +$/, "", $2); print $2}'
}

# ============================================================================
# Empty registry
# ============================================================================

@test "list: empty registry shows help message" {
  run run_list
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "No tools registered"
}

# ============================================================================
# Basic output
# ============================================================================

@test "list: shows registered tools in table" {
  create_test_repo "alpha" "2024-01-01T00:00:00+00:00"
  shiv_register "alpha" "$SHIV_PACKAGES_DIR/alpha"

  run run_list
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "alpha"
}

@test "list: shows aliases in table" {
  create_test_repo "alpha" "2024-01-01T00:00:00+00:00"
  shiv_register "alpha" "$SHIV_PACKAGES_DIR/alpha" "a"

  run run_list
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "a"
}

@test "list: shows branch name" {
  create_test_repo "alpha" "2024-01-01T00:00:00+00:00" "develop"
  shiv_register "alpha" "$SHIV_PACKAGES_DIR/alpha"

  run run_list
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "develop"
}

@test "list: shows commit hash" {
  create_test_repo "alpha" "2024-01-01T00:00:00+00:00"
  shiv_register "alpha" "$SHIV_PACKAGES_DIR/alpha"

  local expected_hash
  expected_hash=$(git -C "$SHIV_PACKAGES_DIR/alpha" rev-parse --short HEAD)

  run run_list
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "$expected_hash"
}

@test "list: shows tag as version when present" {
  create_test_repo "alpha" "2024-01-01T00:00:00+00:00"
  git -C "$SHIV_PACKAGES_DIR/alpha" tag -a "v1.0.0" -m "v1.0.0"
  shiv_register "alpha" "$SHIV_PACKAGES_DIR/alpha"

  run run_list
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "v1.0.0"
}

@test "list: marks dirty working tree with asterisk" {
  create_test_repo "alpha" "2024-01-01T00:00:00+00:00"
  shiv_register "alpha" "$SHIV_PACKAGES_DIR/alpha"

  # Create an uncommitted file
  touch "$SHIV_PACKAGES_DIR/alpha/dirty.txt"

  run run_list
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '\*'
}

@test "list: handles non-git directory gracefully" {
  local repo_dir="$SHIV_PACKAGES_DIR/nogit"
  mkdir -p "$repo_dir"
  shiv_register "nogit" "$repo_dir"

  run run_list
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "nogit"
}

# ============================================================================
# Sort by name
# ============================================================================

@test "list: default sort is alphabetical by name" {
  create_test_repo "charlie" "2024-03-01T00:00:00+00:00"
  create_test_repo "alpha" "2024-01-01T00:00:00+00:00"
  create_test_repo "bravo" "2024-02-01T00:00:00+00:00"
  shiv_register "charlie" "$SHIV_PACKAGES_DIR/charlie"
  shiv_register "alpha" "$SHIV_PACKAGES_DIR/alpha"
  shiv_register "bravo" "$SHIV_PACKAGES_DIR/bravo"

  run run_list
  [ "$status" -eq 0 ]

  packages=()
  while IFS= read -r _pkg; do
    [ -n "$_pkg" ] && packages+=("$_pkg")
  done < <(echo "$output" | extract_packages)
  [ "${packages[0]}" = "alpha" ]
  [ "${packages[1]}" = "bravo" ]
  [ "${packages[2]}" = "charlie" ]
}

@test "list: sort by name descending" {
  create_test_repo "alpha" "2024-01-01T00:00:00+00:00"
  create_test_repo "bravo" "2024-02-01T00:00:00+00:00"
  create_test_repo "charlie" "2024-03-01T00:00:00+00:00"
  shiv_register "alpha" "$SHIV_PACKAGES_DIR/alpha"
  shiv_register "bravo" "$SHIV_PACKAGES_DIR/bravo"
  shiv_register "charlie" "$SHIV_PACKAGES_DIR/charlie"

  run run_list --sort name --desc
  [ "$status" -eq 0 ]

  packages=()
  while IFS= read -r _pkg; do
    [ -n "$_pkg" ] && packages+=("$_pkg")
  done < <(echo "$output" | extract_packages)
  [ "${packages[0]}" = "charlie" ]
  [ "${packages[1]}" = "bravo" ]
  [ "${packages[2]}" = "alpha" ]
}

# ============================================================================
# Sort by updated
# ============================================================================

@test "list: sort by updated defaults to most recent first" {
  create_test_repo "old" "2024-01-01T00:00:00+00:00"
  create_test_repo "mid" "2024-02-01T00:00:00+00:00"
  create_test_repo "new" "2024-03-01T00:00:00+00:00"
  shiv_register "old" "$SHIV_PACKAGES_DIR/old"
  shiv_register "mid" "$SHIV_PACKAGES_DIR/mid"
  shiv_register "new" "$SHIV_PACKAGES_DIR/new"

  run run_list --sort updated
  [ "$status" -eq 0 ]

  packages=()
  while IFS= read -r _pkg; do
    [ -n "$_pkg" ] && packages+=("$_pkg")
  done < <(echo "$output" | extract_packages)
  [ "${packages[0]}" = "new" ]
  [ "${packages[1]}" = "mid" ]
  [ "${packages[2]}" = "old" ]
}

@test "list: sort by updated ascending shows oldest first" {
  create_test_repo "old" "2024-01-01T00:00:00+00:00"
  create_test_repo "mid" "2024-02-01T00:00:00+00:00"
  create_test_repo "new" "2024-03-01T00:00:00+00:00"
  shiv_register "old" "$SHIV_PACKAGES_DIR/old"
  shiv_register "mid" "$SHIV_PACKAGES_DIR/mid"
  shiv_register "new" "$SHIV_PACKAGES_DIR/new"

  run run_list --sort updated --asc
  [ "$status" -eq 0 ]

  packages=()
  while IFS= read -r _pkg; do
    [ -n "$_pkg" ] && packages+=("$_pkg")
  done < <(echo "$output" | extract_packages)
  [ "${packages[0]}" = "old" ]
  [ "${packages[1]}" = "mid" ]
  [ "${packages[2]}" = "new" ]
}

# ============================================================================
# Invalid sort field
# ============================================================================

@test "list: rejects unknown sort field" {
  create_test_repo "alpha" "2024-01-01T00:00:00+00:00"
  shiv_register "alpha" "$SHIV_PACKAGES_DIR/alpha"

  run run_list --sort bogus
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "unknown sort field"
}
