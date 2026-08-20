#!/usr/bin/env bats
# Cross-command package-root resolution contract

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
  export CALLER_DIR="$TEST_HOME/project"
  export GLOBAL_REPO="$SHIV_PACKAGES_DIR/alpha"
  export MISE_REPO="$TEST_HOME/.local/share/mise/installs/shiv-alpha/1.0.0/packages/alpha"
  export MISE_EXECUTABLE="$TEST_HOME/.local/share/mise/installs/shiv-alpha/1.0.0/bin/alpha"

  mkdir -p "$SHIV_BIN_DIR" "$CALLER_DIR"
  shiv_init_registry
  setup_shiv_on_path
  mock_gum_formatting

  export MISE_BIN="$BATS_TEST_TMPDIR/fake-mise"
  create_fake_mise "$MISE_BIN"
  create_simultaneous_package_roots
}

create_fake_mise() {
  local fake_mise="$1"

  cat > "$fake_mise" <<'MOCK'
#!/usr/bin/env bash
if [ "${1:-}" = "-C" ] && [ "${2:-}" = "${CALLER_DIR:-}" ]; then
  if [ "${3:-}" = "ls" ] && [ "${4:-}" = "--json" ]; then
    case "${FAKE_MISE_LS_MODE:-ok}" in
      fail)
        echo "mise inventory failed" >&2
        exit 1
        ;;
      invalid)
        printf '%s\n' '{invalid inventory'
        exit 0
        ;;
    esac
    printf '%s\n' '{"shiv:alpha":[{"active":true}]}'
    exit 0
  fi
  if [ "${3:-}" = "which" ] && [ "${4:-}" = "alpha" ]; then
    if [ "${FAKE_MISE_WHICH_MODE:-ok}" = "fail" ]; then
      echo "mise package resolution failed" >&2
      exit 1
    fi
    printf '%s\n' "$MISE_EXECUTABLE"
    exit 0
  fi
fi

echo "mise ERROR ${4:-} is not active" >&2
exit 1
MOCK
  chmod +x "$fake_mise"
}

create_simultaneous_package_roots() {
  local bare_repo="$TEST_HOME/remotes/alpha.git"
  local seed_repo="$TEST_HOME/seed"
  local shim_bin

  mkdir -p "$bare_repo" "$seed_repo"
  git -C "$bare_repo" init -q --bare -b main
  git -C "$seed_repo" init -q -b main
  git -C "$seed_repo" config user.email "test@test.com"
  git -C "$seed_repo" config user.name "Test"
  printf 'initial\n' > "$seed_repo/README.md"
  git -C "$seed_repo" add README.md
  git -C "$seed_repo" commit -q -m "initial"
  git -C "$seed_repo" remote add origin "$bare_repo"
  git -C "$seed_repo" push -q -u origin main

  git clone -q "$bare_repo" "$GLOBAL_REPO"
  git clone -q "$bare_repo" "$MISE_REPO"
  SHIV_REF=main SHIV_REF_MODE=branch shiv_register "alpha" "$GLOBAL_REPO"

  shim_bin="$SHIV_BIN_DIR"
  SHIV_BIN_DIR="$(dirname "$MISE_EXECUTABLE")" shiv_create_shim "alpha" "$MISE_REPO"
  SHIV_BIN_DIR="$shim_bin"

  printf 'upstream\n' >> "$seed_repo/README.md"
  git -C "$seed_repo" add README.md
  git -C "$seed_repo" commit -q -m "upstream"
  git -C "$seed_repo" push -q origin main
}

create_registry_package_before_conflict() {
  local bare_repo="$TEST_HOME/remotes/beta.git"
  local seed_repo="$TEST_HOME/seeds/beta"

  export BETA_REPO="$SHIV_PACKAGES_DIR/beta"
  shiv_unregister "alpha"

  mkdir -p "$bare_repo" "$seed_repo"
  git -C "$bare_repo" init -q --bare -b main
  git -C "$seed_repo" init -q -b main
  git -C "$seed_repo" config user.email "test@test.com"
  git -C "$seed_repo" config user.name "Test"
  printf 'initial\n' > "$seed_repo/README.md"
  git -C "$seed_repo" add README.md
  git -C "$seed_repo" commit -q -m "initial"
  git -C "$seed_repo" remote add origin "$bare_repo"
  git -C "$seed_repo" push -q -u origin main
  git clone -q "$bare_repo" "$BETA_REPO"

  SHIV_REF=main SHIV_REF_MODE=branch shiv_register "beta" "$BETA_REPO"
  SHIV_REF=main SHIV_REF_MODE=branch shiv_register "alpha" "$GLOBAL_REPO"

  printf 'upstream\n' >> "$seed_repo/README.md"
  git -C "$seed_repo" add README.md
  git -C "$seed_repo" commit -q -m "upstream"
  git -C "$seed_repo" push -q origin main
}

run_shiv_from_caller() {
  cd "$CALLER_DIR"
  shiv "$@" 2>&1
}

@test "resolution contract: update and list reject a different active mise root" {
  local global_before mise_before beta_before active_root active_canonical global_canonical
  global_before=$(git -C "$GLOBAL_REPO" rev-parse HEAD)
  mise_before=$(git -C "$MISE_REPO" rev-parse HEAD)
  active_root="$MISE_REPO"
  active_canonical=$(cd "$MISE_REPO" && pwd -P)
  global_canonical=$(cd "$GLOBAL_REPO" && pwd -P)

  run run_shiv_from_caller which alpha
  [ "$status" -eq 0 ]
  [ "$output" = "$active_root" ]

  create_registry_package_before_conflict
  beta_before=$(git -C "$BETA_REPO" rev-parse HEAD)

  run run_shiv_from_caller update
  [ "$status" -eq 1 ]
  [[ "$output" == *"active mise package root differs from the global registry"* ]]
  [[ "$output" != *"✓ beta"* ]]
  [ "$(git -C "$BETA_REPO" rev-parse HEAD)" = "$beta_before" ]
  [ "$(git -C "$GLOBAL_REPO" rev-parse HEAD)" = "$global_before" ]
  [ "$(git -C "$MISE_REPO" rev-parse HEAD)" = "$mise_before" ]

  run run_shiv_from_caller update alpha
  [ "$status" -eq 1 ]
  [[ "$output" == *"active mise package root differs from the global registry"* ]]
  [[ "$output" == *"$active_canonical"* ]]
  [[ "$output" == *"$global_canonical"* ]]
  [[ "$output" != *"✓ alpha"* ]]
  [ "$(git -C "$GLOBAL_REPO" rev-parse HEAD)" = "$global_before" ]
  [ "$(git -C "$MISE_REPO" rev-parse HEAD)" = "$mise_before" ]

  run run_shiv_from_caller list
  [ "$status" -eq 1 ]
  [[ "$output" == *"active mise package root differs from the global registry"* ]]
  [[ "$output" == *"$active_canonical"* ]]
  [[ "$output" == *"$global_canonical"* ]]
  [[ "$output" != *"Installed packages"* ]]
}

@test "resolution contract: update and list fail closed when mise inventory is unavailable" {
  local global_before
  global_before=$(git -C "$GLOBAL_REPO" rev-parse HEAD)

  export FAKE_MISE_LS_MODE=fail
  run run_shiv_from_caller update
  [ "$status" -eq 1 ]
  [[ "$output" == *"failed to inspect active mise tools"* ]]
  [[ "$output" != *"✓ alpha"* ]]
  [ "$(git -C "$GLOBAL_REPO" rev-parse HEAD)" = "$global_before" ]

  export FAKE_MISE_LS_MODE=invalid
  run run_shiv_from_caller list
  [ "$status" -eq 1 ]
  [[ "$output" == *"mise returned invalid tool inventory"* ]]
  [[ "$output" != *"Installed packages"* ]]
  [ "$(git -C "$GLOBAL_REPO" rev-parse HEAD)" = "$global_before" ]

  export FAKE_MISE_LS_MODE=ok
  export FAKE_MISE_WHICH_MODE=fail
  run run_shiv_from_caller update
  [ "$status" -eq 1 ]
  [[ "$output" == *"failed to resolve active mise package 'shiv:alpha'"* ]]
  [[ "$output" != *"✓ alpha"* ]]
  [ "$(git -C "$GLOBAL_REPO" rev-parse HEAD)" = "$global_before" ]
}

@test "resolution contract: update and list accept the same physical package root" {
  local active_alias="$TEST_HOME/active-alpha"
  local shim_bin="$SHIV_BIN_DIR"

  ln -s "$GLOBAL_REPO" "$active_alias"
  SHIV_BIN_DIR="$(dirname "$MISE_EXECUTABLE")" shiv_create_shim "alpha" "$active_alias"
  SHIV_BIN_DIR="$shim_bin"

  run run_shiv_from_caller update alpha
  [ "$status" -eq 0 ]
  [[ "$output" == *"✓ alpha"* ]]
  [ "$(git -C "$GLOBAL_REPO" rev-parse HEAD)" = "$(git -C "$GLOBAL_REPO" rev-parse origin/main)" ]

  run run_shiv_from_caller list
  [ "$status" -eq 0 ]
  [[ "$output" == *"alpha"* ]]
}
