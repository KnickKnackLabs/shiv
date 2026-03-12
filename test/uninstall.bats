#!/usr/bin/env bats
# shiv uninstall test suite

REPO_DIR="$BATS_TEST_DIRNAME/.."
UNINSTALL_TASK="$REPO_DIR/.mise/tasks/uninstall"

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

  export SHIV_SKIP_CACHE=1
}

teardown() {
  rm -rf "$TEST_HOME"
}

# Helper: create a minimal installed package (repo, shim, registry, cache)
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

  # Create a cache file
  mkdir -p "$SHIV_CACHE_DIR/completions"
  printf 'hello\tSay hello\n' > "$SHIV_CACHE_DIR/completions/$name.cache"

  # Create alias symlinks if provided
  local aliases=("$@")
  if [ ${#aliases[@]} -gt 0 ]; then
    shiv_create_alias_symlinks "$name" "${aliases[@]}"
  fi
}

# Helper: create an installed package with a bare remote (so @{upstream} works)
create_installed_package_with_remote() {
  local name="$1"
  local repo_dir="$SHIV_PACKAGES_DIR/$name"
  local bare_dir="$TEST_HOME/remotes/$name.git"

  # Create bare remote
  mkdir -p "$bare_dir"
  git -C "$bare_dir" init -q --bare

  # Clone it (sets up tracking automatically)
  git clone -q "$bare_dir" "$repo_dir"
  git -C "$repo_dir" config user.email "test@test.com"
  git -C "$repo_dir" config user.name "Test"
  touch "$repo_dir/README.md"
  git -C "$repo_dir" add .
  git -C "$repo_dir" commit -q -m "init"
  git -C "$repo_dir" push -q

  shift
  shiv_register "$name" "$repo_dir" "$@"
  shiv_create_shim "$name" "$repo_dir"

  # Create a cache file
  mkdir -p "$SHIV_CACHE_DIR/completions"
  printf 'hello\tSay hello\n' > "$SHIV_CACHE_DIR/completions/$name.cache"

  # Create alias symlinks if provided
  local aliases=("$@")
  if [ ${#aliases[@]} -gt 0 ]; then
    shiv_create_alias_symlinks "$name" "${aliases[@]}"
  fi
}

# Helper: run the uninstall task
run_uninstall() {
  local name="$1"
  local yes="${2:-false}"
  local force="${3:-false}"
  usage_name="$name" usage_yes="$yes" usage_force="$force" bash "$UNINSTALL_TASK" 2>&1
}

# Helper: create a mock gum that auto-confirms or auto-denies
mock_gum_confirm() {
  local exit_code="$1"  # 0 = confirm, 1 = deny
  mkdir -p "$TEST_HOME/mock-bin"
  cat > "$TEST_HOME/mock-bin/gum" <<MOCK
#!/usr/bin/env bash
if [ "\$1" = "confirm" ]; then
  exit $exit_code
fi
# Pass through to real gum for non-confirm commands (e.g., gum table, gum style)
exec "$(command -v gum)" "\$@"
MOCK
  chmod +x "$TEST_HOME/mock-bin/gum"
  export PATH="$TEST_HOME/mock-bin:$PATH"
}

# ============================================================================
# Unknown package
# ============================================================================

@test "uninstall: rejects unknown package" {
  run run_uninstall "nonexistent"
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "not a registered package"
}

# ============================================================================
# Self-protection
# ============================================================================

@test "uninstall: refuses shiv when other packages installed" {
  create_installed_package "shiv"
  create_installed_package "alpha"

  run run_uninstall "shiv"
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "1 package(s) still installed"
  echo "$output" | grep -q "\-\-force"
  # Should show the other package in a table
  echo "$output" | grep -q "alpha"
}

@test "uninstall: self-protection table shows all other packages" {
  create_installed_package "shiv"
  create_installed_package "alpha"
  create_installed_package "bravo"

  run run_uninstall "shiv"
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "2 package(s) still installed"
  echo "$output" | grep -q "alpha"
  echo "$output" | grep -q "bravo"
}

@test "uninstall: allows shiv when no other packages" {
  create_installed_package "shiv"
  mock_gum_confirm 0

  run run_uninstall "shiv"
  [ "$status" -eq 0 ]
  [ ! -f "$SHIV_BIN_DIR/shiv" ]
}

@test "uninstall: --force overrides shiv self-protection" {
  create_installed_package "shiv"
  create_installed_package "alpha"

  run run_uninstall "shiv" "false" "true"
  [ "$status" -eq 0 ]
  [ ! -f "$SHIV_BIN_DIR/shiv" ]
  # alpha should still be installed
  [ -f "$SHIV_BIN_DIR/alpha" ]
}

# ============================================================================
# Summary card
# ============================================================================

@test "uninstall: summary card shows package details" {
  create_installed_package "alpha"

  run run_uninstall "alpha" "true"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "PACKAGE"
  echo "$output" | grep -q "alpha"
  echo "$output" | grep -q "PATH"
  echo "$output" | grep -q "SHIM"
}

@test "uninstall: summary card shows aliases" {
  create_installed_package "alpha" "a" "al"

  run run_uninstall "alpha" "true"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "a al"
}

@test "uninstall: summary card shows not found for missing shim" {
  create_installed_package "alpha"
  rm "$SHIV_BIN_DIR/alpha"

  run run_uninstall "alpha" "true"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "not found"
}

@test "uninstall: summary card shows not found for missing path" {
  # Register a package pointing to a nonexistent path
  shiv_register "gone" "/tmp/nonexistent-repo-$$"
  shiv_create_shim "gone" "/tmp/nonexistent-repo-$$"

  run run_uninstall "gone" "true"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "not found"
}

# ============================================================================
# -y flag (skip confirmation)
# ============================================================================

@test "uninstall: -y removes shim" {
  create_installed_package "alpha"
  [ -f "$SHIV_BIN_DIR/alpha" ]

  run run_uninstall "alpha" "true"
  [ "$status" -eq 0 ]
  [ ! -f "$SHIV_BIN_DIR/alpha" ]
}

@test "uninstall: -y deregisters from registry" {
  create_installed_package "alpha"
  [ -n "$(shiv_registry_path "alpha")" ]

  run_uninstall "alpha" "true"
  [ -z "$(shiv_registry_path "alpha")" ]
}

@test "uninstall: -y removes cache" {
  create_installed_package "alpha"
  [ -f "$SHIV_CACHE_DIR/completions/alpha.cache" ]

  run_uninstall "alpha" "true"
  [ ! -f "$SHIV_CACHE_DIR/completions/alpha.cache" ]
}

@test "uninstall: -y removes alias symlinks" {
  create_installed_package "alpha" "a" "al"
  [ -L "$SHIV_BIN_DIR/a" ]
  [ -L "$SHIV_BIN_DIR/al" ]

  run_uninstall "alpha" "true"
  [ ! -L "$SHIV_BIN_DIR/a" ]
  [ ! -L "$SHIV_BIN_DIR/al" ]
}

@test "uninstall: shows success message" {
  create_installed_package "alpha"

  run run_uninstall "alpha" "true"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "✓ Uninstalled alpha"
}

# ============================================================================
# Package directory cleanup
# ============================================================================

@test "uninstall: removes clean index-installed package directory" {
  create_installed_package_with_remote "alpha"
  [ -d "$SHIV_PACKAGES_DIR/alpha" ]

  run_uninstall "alpha" "true"
  [ ! -d "$SHIV_PACKAGES_DIR/alpha" ]
}

@test "uninstall: retains dirty index-installed package directory" {
  create_installed_package "alpha"
  touch "$SHIV_PACKAGES_DIR/alpha/uncommitted.txt"

  run run_uninstall "alpha" "true"
  [ "$status" -eq 0 ]
  [ -d "$SHIV_PACKAGES_DIR/alpha" ]
  echo "$output" | grep -q "local changes"
  echo "$output" | grep -q "\-\-force"
}

@test "uninstall: --force removes dirty index-installed package directory" {
  create_installed_package "alpha"
  touch "$SHIV_PACKAGES_DIR/alpha/uncommitted.txt"

  run_uninstall "alpha" "false" "true"
  [ ! -d "$SHIV_PACKAGES_DIR/alpha" ]
}

@test "uninstall: retains index-installed package with unpushed commits" {
  create_installed_package_with_remote "alpha"
  # Make a local commit that isn't pushed
  touch "$SHIV_PACKAGES_DIR/alpha/local-only.txt"
  git -C "$SHIV_PACKAGES_DIR/alpha" add .
  git -C "$SHIV_PACKAGES_DIR/alpha" commit -q -m "local only"

  run run_uninstall "alpha" "true"
  [ "$status" -eq 0 ]
  [ -d "$SHIV_PACKAGES_DIR/alpha" ]
  echo "$output" | grep -q "local changes"
}

@test "uninstall: --force removes index-installed package with unpushed commits" {
  create_installed_package_with_remote "alpha"
  touch "$SHIV_PACKAGES_DIR/alpha/local-only.txt"
  git -C "$SHIV_PACKAGES_DIR/alpha" add .
  git -C "$SHIV_PACKAGES_DIR/alpha" commit -q -m "local only"

  run_uninstall "alpha" "false" "true"
  [ ! -d "$SHIV_PACKAGES_DIR/alpha" ]
}

@test "uninstall: retains index-installed package on local-only branch (no upstream)" {
  create_installed_package_with_remote "alpha"
  # Create a local branch with no upstream
  git -C "$SHIV_PACKAGES_DIR/alpha" checkout -q -b feature/local-work
  touch "$SHIV_PACKAGES_DIR/alpha/experiment.txt"
  git -C "$SHIV_PACKAGES_DIR/alpha" add .
  git -C "$SHIV_PACKAGES_DIR/alpha" commit -q -m "local experiment"

  run run_uninstall "alpha" "true"
  [ "$status" -eq 0 ]
  [ -d "$SHIV_PACKAGES_DIR/alpha" ]
  echo "$output" | grep -q "local changes"
}

@test "uninstall: retains local-path package directory" {
  local repo_dir="$TEST_HOME/my-project"
  mkdir -p "$repo_dir"
  git -C "$repo_dir" init -q -b main
  git -C "$repo_dir" config user.email "test@test.com"
  git -C "$repo_dir" config user.name "Test"
  touch "$repo_dir/README.md"
  git -C "$repo_dir" add .
  git -C "$repo_dir" commit -q -m "init"
  shiv_register "myapp" "$repo_dir"
  shiv_create_shim "myapp" "$repo_dir"

  run run_uninstall "myapp" "true"
  [ "$status" -eq 0 ]
  [ -d "$repo_dir" ]
  echo "$output" | grep -q "Package directory retained"
}

# ============================================================================
# Confirmation prompt
# ============================================================================

@test "uninstall: confirmed prompt proceeds with uninstall" {
  create_installed_package "alpha"
  mock_gum_confirm 0

  run run_uninstall "alpha"
  [ "$status" -eq 0 ]
  [ ! -f "$SHIV_BIN_DIR/alpha" ]
  echo "$output" | grep -q "✓ Uninstalled alpha"
}

@test "uninstall: denied prompt cancels cleanly" {
  create_installed_package "alpha"
  mock_gum_confirm 1

  run run_uninstall "alpha"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Cancelled"
  # Shim should still exist
  [ -f "$SHIV_BIN_DIR/alpha" ]
}

@test "uninstall: -y skips confirmation entirely" {
  create_installed_package "alpha"
  # Mock gum to deny — should be irrelevant with -y
  mock_gum_confirm 1

  run run_uninstall "alpha" "true"
  [ "$status" -eq 0 ]
  [ ! -f "$SHIV_BIN_DIR/alpha" ]
}

@test "uninstall: --force implies -y" {
  create_installed_package "alpha"
  # Mock gum to deny — should be irrelevant with --force
  mock_gum_confirm 1

  run run_uninstall "alpha" "false" "true"
  [ "$status" -eq 0 ]
  [ ! -f "$SHIV_BIN_DIR/alpha" ]
}
