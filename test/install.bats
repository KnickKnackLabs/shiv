#!/usr/bin/env bats
# shiv install test suite

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
  export REMOTES_DIR="$TEST_HOME/remotes"
  export GIT_CONFIG_GLOBAL="$TEST_HOME/gitconfig"

  mkdir -p "$SHIV_BIN_DIR" "$REMOTES_DIR"
  shiv_init_registry
  export REAL_MISE="$(command -v mise)"
  setup_shiv_on_path
  mock_dependency_mise

  # Skip task-cache discovery unless a test exercises generated-shim runtime.
  export SHIV_SKIP_CACHE=1
}


# Most install tests claim Shiv behavior, not Mise's dependency installer.
# Keep the outer public `shiv install` path real while replacing only the bare
# trust/install subprocesses. Dedicated tests below overwrite this mock and
# prove those calls and their environment explicitly.
mock_dependency_mise() {
  cat > "$BATS_TEST_TMPDIR/mock-bin/mise" <<MOCK
#!/usr/bin/env bash
case "\${1:-}" in
  -C) exec "$REAL_MISE" "\$@" ;;
  trust|install) exit 0 ;;
  *) exec "$REAL_MISE" "\$@" ;;
esac
MOCK
  chmod +x "$BATS_TEST_TMPDIR/mock-bin/mise"
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

  # Pre-populate task cache so summary tests avoid task discovery.
  mkdir -p "$SHIV_CACHE_DIR/completions"
  printf 'hello\tSay hello\n' > "$SHIV_CACHE_DIR/completions/$name.cache"

  echo "$repo_dir"
}

# Helper: create a bare remote package with optional release tags.
create_remote_package() {
  local name="$1"
  shift
  local work_dir="$TEST_HOME/work-$name"
  local remote_dir="$REMOTES_DIR/$name.git"

  mkdir -p "$work_dir"
  git -C "$work_dir" init -q -b main
  git -C "$work_dir" config user.email "test@test.com"
  git -C "$work_dir" config user.name "Test"
  touch "$work_dir/README.md"
  git -C "$work_dir" add .
  git -C "$work_dir" commit -q -m "init"

  for tag in "$@"; do
    echo "$tag" > "$work_dir/$tag.txt"
    git -C "$work_dir" add .
    git -C "$work_dir" commit -q -m "$tag"
    git -C "$work_dir" tag -a "$tag" -m "$tag"
  done

  git clone -q --bare "$work_dir" "$remote_dir"
  rm -rf "$work_dir"
}

# Helper: map a source-index GitHub slug to the local bare remote.
configure_remote_source() {
  local name="$1"
  local sources="$TEST_HOME/sources.json"
  printf '{"%s": "TestOrg/%s"}\n' "$name" "$name" > "$sources"
  export SHIV_SOURCES="$sources"
  git config --file "$GIT_CONFIG_GLOBAL" url."$REMOTES_DIR/".insteadOf "https://github.com/TestOrg/"
}

# Helper: add a release tag to an existing bare remote package.
add_remote_package_tag() {
  local name="$1" tag="$2"
  local remote_dir="$REMOTES_DIR/$name.git"
  local tmp_dir="$TEST_HOME/tmp-$name-$tag"

  git clone -q "$remote_dir" "$tmp_dir"
  git -C "$tmp_dir" config user.email "test@test.com"
  git -C "$tmp_dir" config user.name "Test"
  echo "$tag" > "$tmp_dir/$tag.txt"
  git -C "$tmp_dir" add .
  git -C "$tmp_dir" commit -q -m "$tag"
  git -C "$tmp_dir" tag -a "$tag" -m "$tag"
  git -C "$tmp_dir" push -q origin main "$tag"
  rm -rf "$tmp_dir"
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

# Helper: record dependency-setup calls while delegating the outer shiv task
# invocation to the real mise binary.
record_dependency_mise_calls() {
  export MISE_CALL_LOG="$TEST_HOME/mise-calls.log"
  export MISE_ENV_CALL_LOG="$TEST_HOME/mise-env-calls.log"

  cat > "$BATS_TEST_TMPDIR/mock-bin/mise" <<MOCK
#!/usr/bin/env bash
if [ "\${1:-}" = "-C" ] && [ "\${2:-}" = "$REPO_DIR" ]; then
  exec "$REAL_MISE" "\$@"
fi
printf '%s\t%s\n' "\$PWD" "\$*" >> "$MISE_CALL_LOG"
printf '%s\t%s\t%s\n' "\$PWD" "\${MISE_OVERRIDE_CONFIG_FILENAMES-}" "\$*" >> "$MISE_ENV_CALL_LOG"
exit 0
MOCK
  chmod +x "$BATS_TEST_TMPDIR/mock-bin/mise"
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
  [ "$(shiv_registry_ref_mode "myapp")" = "local" ]
}

@test "install: local path install runs mise trust and install" {
  local repo_dir
  repo_dir=$(create_local_repo "myapp")
  record_dependency_mise_calls

  run run_install "myapp" "$repo_dir"
  [ "$status" -eq 0 ]

  grep -F "$(printf '%s\ttrust -q' "$repo_dir")" "$MISE_CALL_LOG"
  grep -F "$(printf '%s\tinstall -q' "$repo_dir")" "$MISE_CALL_LOG"
}

@test "install: dependency setup clears inherited mise config override" {
  local repo_dir parent_config
  repo_dir=$(create_local_repo "myapp")
  record_dependency_mise_calls
  parent_config="$TEST_HOME/parent-config.toml"
  printf '[settings]\nexperimental = true\n' > "$parent_config"
  export MISE_OVERRIDE_CONFIG_FILENAMES="$parent_config"

  run bash -c "cd '$REPO_DIR' && MISE_CONFIG_ROOT='$REPO_DIR' usage_name='myapp' usage_path='$repo_dir' usage_as='' .mise/tasks/install"
  [ "$status" -eq 0 ]

  grep -F "$(printf '%s\t\ttrust -q' "$repo_dir")" "$MISE_ENV_CALL_LOG"
  grep -F "$(printf '%s\t\tinstall -q' "$repo_dir")" "$MISE_ENV_CALL_LOG"
}

@test "install: generated shim clears inherited mise config override at runtime" {
  local repo_dir parent_config task_map
  repo_dir="$TEST_HOME/repos/myapp"
  mkdir -p "$repo_dir/.mise/tasks/hello"
  git -C "$repo_dir" init -q -b main
  git -C "$repo_dir" config user.email "test@test.com"
  git -C "$repo_dir" config user.name "Test"
  printf '[tools]\n' > "$repo_dir/mise.toml"
  cat > "$repo_dir/.mise/tasks/hello/world" <<'TASK'
#!/usr/bin/env bash
echo package-world
TASK
  chmod +x "$repo_dir/.mise/tasks/hello/world"
  git -C "$repo_dir" add .
  git -C "$repo_dir" commit -q -m "init"

  run_install "myapp" "$repo_dir"

  # Isolate the generated shim's runtime cache after dependency setup. Applying
  # this earlier hides Mise's own tool metadata while the installer renders its
  # Gum summary, which is outside this test's runtime-override claim.
  export XDG_CACHE_HOME="$TEST_HOME/.cache"
  rm -f "$SHIV_CACHE_DIR/tasks/myapp"

  parent_config="$TEST_HOME/parent-config.toml"
  cat > "$parent_config" <<'TOML'
[tasks.parent]
run = "echo parent-task-ran"
TOML
  mise trust "$parent_config" 2>/dev/null
  export MISE_OVERRIDE_CONFIG_FILENAMES="$parent_config"

  run "$SHIV_BIN_DIR/myapp" hello world
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "package-world"

  task_map="$SHIV_CACHE_DIR/tasks/myapp"
  grep -q "^hello world$" "$task_map"
  ! grep -q "^parent$" "$task_map"

  run "$SHIV_BIN_DIR/myapp" parent
  [ "$status" -ne 0 ]
  ! echo "$output" | grep -q "parent-task-ran"
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

@test "install: shim warning includes the args as 'mise run ...' suggestion" {
  # Regression: _shiv_check_cwd used to be called with no args, so $* inside
  # the function was empty and the warning printed as 'mise run ' with a
  # trailing space and no actionable suggestion.
  local repo_dir
  repo_dir=$(create_local_repo "myapp")
  run_install "myapp" "$repo_dir"

  local fake_dir="$TEST_HOME/projects/myapp"
  mkdir -p "$fake_dir"

  run bash -c "cd '$fake_dir' && '$SHIV_BIN_DIR/myapp' hello world 2>&1"
  echo "$output" | grep -qE "to run from this directory instead: mise run hello world($|[^a-z])"
}

@test "install: shim does not warn from unrelated directory" {
  local repo_dir
  repo_dir=$(create_local_repo "myapp")
  run_install "myapp" "$repo_dir"

  run bash -c "cd /tmp && '$SHIV_BIN_DIR/myapp' hello 2>&1"
  ! echo "$output" | grep -q "warning"
}

# ============================================================================
# Package-index release and ref installs
# ============================================================================

@test "install: bare package install resolves to latest release tag" {
  create_remote_package "alpha" "v1.0.0" "v1.2.0"
  configure_remote_source "alpha"

  run run_install "alpha"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "✓ Installed alpha@v1.2.0"
  [ "$(shiv_registry_ref "alpha")" = "v1.2.0" ]
  [ "$(shiv_registry_ref_mode "alpha")" = "release" ]
  [ "$(git -C "$SHIV_PACKAGES_DIR/alpha" describe --tags --exact-match HEAD)" = "v1.2.0" ]
}

@test "install: @latest resolves to latest release tag" {
  create_remote_package "alpha" "v0.9.0" "v1.0.0"
  configure_remote_source "alpha"

  run run_install "alpha@latest"
  [ "$status" -eq 0 ]
  [ "$(shiv_registry_ref "alpha")" = "v1.0.0" ]
  [ "$(shiv_registry_ref_mode "alpha")" = "release" ]
}

@test "install: @main explicitly tracks the main branch" {
  create_remote_package "alpha" "v1.0.0"
  configure_remote_source "alpha"

  run run_install "alpha@main"
  [ "$status" -eq 0 ]
  [ "$(shiv_registry_ref "alpha")" = "main" ]
  [ "$(shiv_registry_ref_mode "alpha")" = "branch" ]
  [ "$(git -C "$SHIV_PACKAGES_DIR/alpha" rev-parse --abbrev-ref HEAD)" = "main" ]
}

@test "install: reinstalling release channel fetches newly available tags" {
  create_remote_package "alpha" "v1.0.0"
  configure_remote_source "alpha"

  run_install "alpha"
  add_remote_package_tag "alpha" "v1.1.0"

  run run_install "alpha"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "✓ Installed alpha@v1.1.0"
  [ "$(shiv_registry_ref "alpha")" = "v1.1.0" ]
  [ "$(shiv_registry_ref_mode "alpha")" = "release" ]
  [ "$(git -C "$SHIV_PACKAGES_DIR/alpha" describe --tags --exact-match HEAD)" = "v1.1.0" ]
}

@test "install: switching an existing release install to branch tracking fetches the branch" {
  create_remote_package "alpha" "v1.0.0"
  configure_remote_source "alpha"

  run_install "alpha"

  run run_install "alpha@main"
  [ "$status" -eq 0 ]
  [ "$(shiv_registry_ref "alpha")" = "main" ]
  [ "$(shiv_registry_ref_mode "alpha")" = "branch" ]
  [ "$(git -C "$SHIV_PACKAGES_DIR/alpha" rev-parse --abbrev-ref HEAD)" = "main" ]
}

@test "install: switching back to branch tracking reuses a clean local branch" {
  create_remote_package "alpha" "v1.0.0"
  configure_remote_source "alpha"

  run_install "alpha@main"
  run_install "alpha@v1.0.0"

  run run_install "alpha@main"
  [ "$status" -eq 0 ]
  [ "$(shiv_registry_ref "alpha")" = "main" ]
  [ "$(shiv_registry_ref_mode "alpha")" = "branch" ]
  [ "$(git -C "$SHIV_PACKAGES_DIR/alpha" rev-parse --abbrev-ref HEAD)" = "main" ]
}

@test "install: release install does not print detached-HEAD advice" {
  create_remote_package "alpha" "v1.0.0" "v1.2.0"
  configure_remote_source "alpha"

  run run_install "alpha"
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q "detached HEAD"
  ! echo "$output" | grep -q "advice.detachedHead"
  ! echo "$output" | grep -q "is not a commit"
}

@test "install: exact tag install does not print detached-HEAD advice" {
  create_remote_package "alpha" "v1.0.0"
  configure_remote_source "alpha"

  run run_install "alpha@v1.0.0"
  [ "$status" -eq 0 ]
  [ "$(shiv_registry_ref_mode "alpha")" = "tag" ]
  ! echo "$output" | grep -q "detached HEAD"
  ! echo "$output" | grep -q "advice.detachedHead"
  ! echo "$output" | grep -q "is not a commit"
}

@test "install: annotated tag install emits no 'is not a commit' warning" {
  # create_remote_package tags are annotated (git tag -a), like signed releases.
  create_remote_package "alpha" "v1.0.0" "v1.2.0"
  configure_remote_source "alpha"

  run run_install "alpha"
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q "is not a commit"
  # Tag ref must still resolve locally (used by list/describe) at the right commit
  [ "$(git -C "$SHIV_PACKAGES_DIR/alpha" describe --tags --exact-match HEAD)" = "v1.2.0" ]
}

@test "install: switching release channel to a new tag does not print detached-HEAD advice" {
  create_remote_package "alpha" "v1.0.0"
  configure_remote_source "alpha"

  run_install "alpha"
  add_remote_package_tag "alpha" "v1.1.0"

  run run_install "alpha"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "✓ Installed alpha@v1.1.0"
  ! echo "$output" | grep -q "detached HEAD"
  ! echo "$output" | grep -q "advice.detachedHead"
}

@test "install: switching to branch tracking refuses local branch commits" {
  create_remote_package "alpha" "v1.0.0"
  configure_remote_source "alpha"

  run_install "alpha@main"
  git -C "$SHIV_PACKAGES_DIR/alpha" config user.email "test@test.com"
  git -C "$SHIV_PACKAGES_DIR/alpha" config user.name "Test"
  echo "local work" > "$SHIV_PACKAGES_DIR/alpha/local.txt"
  git -C "$SHIV_PACKAGES_DIR/alpha" add .
  git -C "$SHIV_PACKAGES_DIR/alpha" commit -q -m "local work"
  run_install "alpha@v1.0.0"

  run run_install "alpha@main"
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "Refusing to switch alpha to main"
  echo "$output" | grep -q "local branch main has commits not on origin/main"
  echo "$output" | grep -q "git -C .* log --oneline origin/main..main"
  echo "$output" | grep -q "git -C .* reset --hard origin/main"
  [ "$(shiv_registry_ref "alpha")" = "v1.0.0" ]
  [ "$(shiv_registry_ref_mode "alpha")" = "tag" ]
}

@test "install: exact tag is recorded as a pinned tag" {
  create_remote_package "alpha" "v1.0.0" "v1.2.0"
  configure_remote_source "alpha"

  run run_install "alpha@v1.0.0"
  [ "$status" -eq 0 ]
  [ "$(shiv_registry_ref "alpha")" = "v1.0.0" ]
  [ "$(shiv_registry_ref_mode "alpha")" = "tag" ]
  [ "$(git -C "$SHIV_PACKAGES_DIR/alpha" describe --tags --exact-match HEAD)" = "v1.0.0" ]
}

@test "install: package with no release tags tells user to choose a branch" {
  create_remote_package "alpha"
  configure_remote_source "alpha"

  run run_install "alpha"
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "No release tags found for alpha"
  echo "$output" | grep -q "shiv install alpha@main"
  [ ! -d "$SHIV_PACKAGES_DIR/alpha" ]
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
