#!/usr/bin/env bats

# Real public tasks with failure-injected registry producers. Partial producer
# output must not become a successful empty or incomplete operation.
REPO_DIR="$BATS_TEST_DIRNAME/.."
load helpers

setup() {
  export INPUT_FIXTURE="$BATS_TEST_TMPDIR/input-fixture"
  export SHIV_CONFIG_DIR="$INPUT_FIXTURE/config"
  export SHIV_REGISTRY="$SHIV_CONFIG_DIR/registry.json"
  export SHIV_BIN_DIR="$INPUT_FIXTURE/bin"
  export SHIV_CACHE_DIR="$INPUT_FIXTURE/cache"
  mkdir -p "$INPUT_FIXTURE/lib" "$INPUT_FIXTURE/.mise/tasks/completions" "$SHIV_CONFIG_DIR" "$SHIV_BIN_DIR"

  local task shell
  for task in list outdated update doctor uninstall install; do
    cp "$REPO_DIR/.mise/tasks/$task" "$INPUT_FIXTURE/.mise/tasks/$task"
  done
  for shell in bash zsh fish; do
    cp "$REPO_DIR/.mise/tasks/completions/$shell" "$INPUT_FIXTURE/.mise/tasks/completions/$shell"
  done
  cp "$REPO_DIR/lib/format.sh" "$INPUT_FIXTURE/lib/format.sh"
  printf '[task_config]\nincludes = [".mise/tasks"]\n' > "$INPUT_FIXTURE/mise.toml"
  export MISE_TRUSTED_CONFIG_PATHS="$INPUT_FIXTURE/mise.toml${MISE_TRUSTED_CONFIG_PATHS:+:$MISE_TRUSTED_CONFIG_PATHS}"
  printf '{"shiv":{"path":"/fictional/shiv"},"myapp":{"path":"/fictional/myapp"}}\n' > "$SHIV_REGISTRY"

  printf 'source %q\n' "$REPO_DIR/lib/shim.sh" > "$INPUT_FIXTURE/lib/shim.sh"
  cat >> "$INPUT_FIXTURE/lib/shim.sh" <<'SH'
shiv_registry_entries() {
  printf 'myapp\t/fictional/myapp\tmain\n'
  printf 'fictional registry read failed\n' >&2
  return 23
}
shiv_registry_aliases() {
  printf 'myapp-alias\n'
  printf 'fictional alias read failed\n' >&2
  return 23
}
shiv_assert_active_packages_match_registry() { return 0; }
SH
}

@test "task inputs: registry failures stop list, outdated, update and doctor" {
  local task
  for task in list outdated update doctor; do
    run shiv_input_fixture "$task"
    [ "$status" -ne 0 ]
    [[ "$output" == *"fictional registry read failed"* ]]
  done
}

@test "task inputs: uninstall refuses a failed registry read before removal" {
  touch "$SHIV_BIN_DIR/shiv"
  run shiv_input_fixture uninstall shiv
  [ "$status" -ne 0 ]
  [[ "$output" == *"fictional registry read failed"* ]]
  [ -f "$SHIV_BIN_DIR/shiv" ]
}

@test "task inputs: uninstall refuses failed alias metadata before removal" {
  touch "$SHIV_BIN_DIR/myapp"
  run shiv_input_fixture uninstall myapp --yes
  [ "$status" -ne 0 ]
  [[ "$output" == *"fictional alias read failed"* ]]
  [ -f "$SHIV_BIN_DIR/myapp" ]
}

@test "task inputs: completion generators report failed registry reads" {
  local shell
  for shell in bash zsh fish; do
    run shiv_input_fixture "completions:$shell"
    [ "$status" -ne 0 ]
    [[ "$output" == *"fictional registry read failed"* ]]
  done
}

@test "task inputs: completion generators report failed alias reads" {
  cat >> "$INPUT_FIXTURE/lib/shim.sh" <<'SH'
shiv_registry_entries() { printf 'myapp\t/fictional/myapp\tmain\n'; }
SH
  local shell
  for shell in bash zsh fish; do
    run shiv_input_fixture "completions:$shell"
    [ "$status" -ne 0 ]
    [[ "$output" == *"fictional alias read failed"* ]]
  done
}

@test "sources: failed release lookup does not disclose URL or Git stderr" {
  source "$REPO_DIR/lib/sources.sh"
  git() {
    printf 'fatal: fictional credential-bearing URL: %s\n' "$*" >&2
    return 1
  }

  run shiv_latest_release_tag_from_url 'https://fictional-user:fictional-secret@example.test/repo.git'
  [ "$status" -eq 2 ]
  [ "$output" = "Error: failed to query release tags" ]
}
