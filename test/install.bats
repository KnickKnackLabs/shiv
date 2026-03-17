#!/usr/bin/env bats
# shiv install test suite

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

  mkdir -p "$SHIV_BIN_DIR"
  shiv_init_registry
  setup_shiv_on_path

  # Skip mise tasks --json in tests (hangs without trusted repo)
  export SHIV_SKIP_CACHE=1
}

teardown() {
  rm -rf "$TEST_HOME"
}

# Helper: create a local repo to install from (simulates local path install)
create_local_repo() {
  local name="$1"
  local repo_dir="$TEST_HOME/repos/$name"

  mkdir -p "$repo_dir"
  git -C "$repo_dir" init -q -b main
  git -C "$repo_dir" config user.email "test@test.com"
  git -C "$repo_dir" config user.name "Test"

  # Create a minimal mise.toml so it looks like a real package
  echo '[tasks.hello]' > "$repo_dir/mise.toml"
  echo 'description = "Say hello"' >> "$repo_dir/mise.toml"
  echo 'run = "echo hi"' >> "$repo_dir/mise.toml"

  git -C "$repo_dir" add .
  git -C "$repo_dir" commit -q -m "init"

  # Pre-populate task cache (avoids mise trust/install in test)
  mkdir -p "$SHIV_CACHE_DIR/completions"
  printf 'hello\tSay hello\n' > "$SHIV_CACHE_DIR/completions/$name.cache"

  echo "$repo_dir"
}


# Helper: run shiv install through the mock shim
run_install() {
  local name="$1"
  local path="${2:-}"
  local as_str="${3:-}"
  local cmd=(shiv install "$name")
  [ -n "$path" ] && cmd+=("$path")
  if [ -n "$as_str" ]; then
    for a in $as_str; do
      cmd+=(--as "$a")
    done
  fi
  "${cmd[@]}" 2>&1
}

# ============================================================================
# Local path install
# ============================================================================

@test "install: local path install shows summary card" {
  local repo_dir
  repo_dir=$(create_local_repo "myapp")

  run run_install "myapp" "$repo_dir"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "✓ Installed myapp"
  # Summary table should contain the key-value pairs
  echo "$output" | grep -q "PACKAGE"
  echo "$output" | grep -q "myapp"
}

@test "install: local path install creates shim" {
  local repo_dir
  repo_dir=$(create_local_repo "myapp")

  run_install "myapp" "$repo_dir"
  [ -f "$SHIV_BIN_DIR/myapp" ]
}

@test "install: local path install registers in registry" {
  local repo_dir
  repo_dir=$(create_local_repo "myapp")

  run_install "myapp" "$repo_dir"
  [ -n "$(shiv_registry_path "myapp")" ]
}

@test "install: shows branch in summary card" {
  local repo_dir="$TEST_HOME/repos/branched"
  mkdir -p "$repo_dir"
  git -C "$repo_dir" init -q -b develop
  git -C "$repo_dir" config user.email "test@test.com"
  git -C "$repo_dir" config user.name "Test"
  echo '[tasks.hello]' > "$repo_dir/mise.toml"
  echo 'run = "echo hi"' >> "$repo_dir/mise.toml"
  git -C "$repo_dir" add .
  git -C "$repo_dir" commit -q -m "init"

  run run_install "branched" "$repo_dir"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "develop"
}

@test "install: shows commit hash in summary card" {
  local repo_dir
  repo_dir=$(create_local_repo "myapp")

  local expected_hash
  expected_hash=$(git -C "$repo_dir" rev-parse --short HEAD)

  run run_install "myapp" "$repo_dir"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "$expected_hash"
}

@test "install: shows tag as version when present" {
  local repo_dir
  repo_dir=$(create_local_repo "myapp")
  git -C "$repo_dir" tag -a "v2.0.0" -m "v2.0.0"

  run run_install "myapp" "$repo_dir"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "v2.0.0"
}

@test "install: shows dirty marker in version" {
  local repo_dir
  repo_dir=$(create_local_repo "myapp")
  touch "$repo_dir/uncommitted.txt"

  run run_install "myapp" "$repo_dir"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '\*'
}

# ============================================================================
# Aliases
# ============================================================================

@test "install: aliases shown in summary card" {
  local repo_dir
  repo_dir=$(create_local_repo "myapp")

  run run_install "myapp" "$repo_dir" "ma mp"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "ma mp"
}

@test "install: alias symlinks are created" {
  local repo_dir
  repo_dir=$(create_local_repo "myapp")

  run_install "myapp" "$repo_dir" "ma"
  [ -L "$SHIV_BIN_DIR/ma" ]
}

# ============================================================================
# Tasks in summary card
# ============================================================================

@test "install: shows available tasks in summary card" {
  local repo_dir
  repo_dir=$(create_local_repo "myapp")

  run run_install "myapp" "$repo_dir"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "TASKS"
  echo "$output" | grep -q "hello"
}

# ============================================================================
# Non-git directory
# ============================================================================

@test "install: handles non-git directory gracefully" {
  local repo_dir="$TEST_HOME/repos/nogit"
  mkdir -p "$repo_dir"
  touch "$repo_dir/mise.toml"

  run run_install "nogit" "$repo_dir"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "✓ Installed nogit"
}

# ============================================================================
# Missing mise.toml
# ============================================================================

@test "install: warns when no mise.toml found" {
  local repo_dir="$TEST_HOME/repos/bare"
  mkdir -p "$repo_dir"
  git -C "$repo_dir" init -q -b main
  git -C "$repo_dir" config user.email "test@test.com"
  git -C "$repo_dir" config user.name "Test"
  touch "$repo_dir/README.md"
  git -C "$repo_dir" add .
  git -C "$repo_dir" commit -q -m "init"

  run run_install "bare" "$repo_dir"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "No mise.toml"
}

# ============================================================================
# Shim CWD warning
# ============================================================================

@test "install: shim warns when run from same-named directory that isn't the package" {
  local repo_dir
  repo_dir=$(create_local_repo "myapp")
  run_install "myapp" "$repo_dir"

  # Create a different directory with the same name
  local fake_dir="$TEST_HOME/projects/myapp"
  mkdir -p "$fake_dir"

  # Run the shim from the fake directory — should warn
  run bash -c "cd '$fake_dir' && '$SHIV_BIN_DIR/myapp' hello 2>&1"
  echo "$output" | grep -q "warning: you're in a directory called 'myapp' but running the shiv-installed copy"
}

@test "install: shim does not warn when run from the actual package directory" {
  local repo_dir
  repo_dir=$(create_local_repo "myapp")
  run_install "myapp" "$repo_dir"

  # Run from the actual shiv package dir — should NOT warn
  local pkg_dir="$SHIV_PACKAGES_DIR/myapp"
  # The install copies to packages dir; if not, use repo_dir
  local run_dir="${pkg_dir}"
  [ -d "$run_dir" ] || run_dir="$repo_dir"

  run bash -c "cd '$run_dir' && '$SHIV_BIN_DIR/myapp' hello 2>&1"
  ! echo "$output" | grep -q "warning"
}

@test "install: shim does not warn from unrelated directory" {
  local repo_dir
  repo_dir=$(create_local_repo "myapp")
  run_install "myapp" "$repo_dir"

  run bash -c "cd /tmp && '$SHIV_BIN_DIR/myapp' hello 2>&1"
  ! echo "$output" | grep -q "warning"
}

# ============================================================================
# Ref re-install behavior
# ============================================================================

@test "install: @main on main branch does not trigger re-clone" {
  # Test the re-clone logic directly: if requested ref matches current branch,
  # the directory should not be removed
  local repo_dir
  repo_dir=$(create_local_repo "myapp")

  # Simulate: tool installed at repo_dir without a ref (registry has no ref)
  shiv_register "myapp" "$repo_dir"
  touch "$repo_dir/.install-marker"

  # Run the re-clone check logic from install
  run bash -c "
    source '$REPO_DIR/lib/registry.sh'
    export SHIV_REGISTRY='$SHIV_REGISTRY'
    EXISTING_REF=\$(shiv_registry_ref myapp)
    CURRENT_BRANCH=\$(git -C '$repo_dir' rev-parse --abbrev-ref HEAD)
    REF=main
    # From install: skip re-clone when ref matches current branch
    if [ \"\$REF\" != \"\$EXISTING_REF\" ] && [ \"\$REF\" != \"\$CURRENT_BRANCH\" ]; then
      rm -rf '$repo_dir'
      echo 'RECLONED'
    else
      echo 'SKIPPED'
    fi
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"SKIPPED"* ]]
  # Directory was not removed
  [ -f "$repo_dir/.install-marker" ]
}

# ============================================================================
# Package not found (index lookup)
# ============================================================================

@test "install: unknown package shows error and available packages table" {
  # Set SHIV_SOURCES to a test sources file
  local sources="$TEST_HOME/sources.json"
  echo '{"alpha": "Org/alpha", "bravo": "Org/bravo"}' > "$sources"
  export SHIV_SOURCES="$sources"

  run run_install "nonexistent"
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "not found in package index"
  # Should show available packages table
  echo "$output" | grep -q "PACKAGE"
  echo "$output" | grep -q "alpha"
  echo "$output" | grep -q "bravo"
}

# ============================================================================
# Default task detection
# ============================================================================

# Helper: create a repo with a named task matching the package name
create_repo_with_named_task() {
  local name="$1"
  local repo_dir="$TEST_HOME/repos/$name"

  mkdir -p "$repo_dir/.mise/tasks"
  git -C "$repo_dir" init -q -b main
  git -C "$repo_dir" config user.email "test@test.com"
  git -C "$repo_dir" config user.name "Test"

  echo '[tools]' > "$repo_dir/mise.toml"

  cat > "$repo_dir/.mise/tasks/$name" <<'TASK'
#!/usr/bin/env bash
#MISE description="The default command"
echo "default-task-ran:$*"
TASK
  chmod +x "$repo_dir/.mise/tasks/$name"

  git -C "$repo_dir" add .
  git -C "$repo_dir" commit -q -m "init"

  mkdir -p "$SHIV_CACHE_DIR/completions"
  printf '%s\tThe default command\n' "$name" > "$SHIV_CACHE_DIR/completions/$name.cache"

  echo "$repo_dir"
}

# Helper: create a repo with a _default task
create_repo_with_default_task() {
  local name="$1"
  local repo_dir="$TEST_HOME/repos/$name"

  mkdir -p "$repo_dir/.mise/tasks"
  git -C "$repo_dir" init -q -b main
  git -C "$repo_dir" config user.email "test@test.com"
  git -C "$repo_dir" config user.name "Test"

  echo '[tools]' > "$repo_dir/mise.toml"

  cat > "$repo_dir/.mise/tasks/_default" <<'TASK'
#!/usr/bin/env bash
#MISE description="The default command"
echo "default-task-ran:$*"
TASK
  chmod +x "$repo_dir/.mise/tasks/_default"

  git -C "$repo_dir" add .
  git -C "$repo_dir" commit -q -m "init"

  mkdir -p "$SHIV_CACHE_DIR/completions"
  printf '_default\tThe default command\n' > "$SHIV_CACHE_DIR/completions/$name.cache"

  echo "$repo_dir"
}

@test "install: shim bakes DEFAULT_TASK when repo has matching named task" {
  local repo_dir
  repo_dir=$(create_repo_with_named_task "calc")
  run_install "calc" "$repo_dir"

  grep -q 'DEFAULT_TASK="calc"' "$SHIV_BIN_DIR/calc"
}

@test "install: shim bakes DEFAULT_TASK when repo has _default task" {
  local repo_dir
  repo_dir=$(create_repo_with_default_task "calc")
  run_install "calc" "$repo_dir"

  grep -q 'DEFAULT_TASK="_default"' "$SHIV_BIN_DIR/calc"
}

@test "install: shim has empty DEFAULT_TASK when no matching task exists" {
  local repo_dir
  repo_dir=$(create_local_repo "myapp")
  run_install "myapp" "$repo_dir"

  grep -q 'DEFAULT_TASK=""' "$SHIV_BIN_DIR/myapp"
}

@test "install: named task takes precedence over _default" {
  local repo_dir="$TEST_HOME/repos/both"
  mkdir -p "$repo_dir/.mise/tasks"
  git -C "$repo_dir" init -q -b main
  git -C "$repo_dir" config user.email "test@test.com"
  git -C "$repo_dir" config user.name "Test"

  echo '[tools]' > "$repo_dir/mise.toml"

  cat > "$repo_dir/.mise/tasks/both" <<'TASK'
#!/usr/bin/env bash
#MISE description="Named task"
echo "named"
TASK
  chmod +x "$repo_dir/.mise/tasks/both"

  cat > "$repo_dir/.mise/tasks/_default" <<'TASK'
#!/usr/bin/env bash
#MISE description="Default task"
echo "default"
TASK
  chmod +x "$repo_dir/.mise/tasks/_default"

  git -C "$repo_dir" add .
  git -C "$repo_dir" commit -q -m "init"
  mkdir -p "$SHIV_CACHE_DIR/completions"
  printf 'both\tNamed task\n_default\tDefault task\n' > "$SHIV_CACHE_DIR/completions/both.cache"

  run_install "both" "$repo_dir"
  grep -q 'DEFAULT_TASK="both"' "$SHIV_BIN_DIR/both"
}
