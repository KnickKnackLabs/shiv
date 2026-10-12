#!/usr/bin/env bats
# Fictional-only restore checks, including the actual Mise source boundary.
REPO_DIR="$BATS_TEST_DIRNAME/.."
load helpers

setup() {
  cd "$BATS_TEST_TMPDIR"
  export PACKAGE="$BATS_TEST_TMPDIR/package with spaces"
  mkdir -p "$PACKAGE"
  export MISE_AUTO_INSTALL=false MISE_TASK_RUN_AUTO_INSTALL=false MISE_OFFLINE=true
  source "$REPO_DIR/lib/caller-env.sh"
  local directory_key
  directory_key=$(shiv_caller_env_key "$(cd "$PACKAGE" && pwd -P)")
  export "SHIV_CALLER_OWNER_$directory_key=6d79617070"
}

write_declaration() {
  printf '[_.shiv]\ncaller_env = %s\n' "$1" > "$PACKAGE/mise.toml"
}

restore() {
  source "$REPO_DIR/lib/env-restore.sh"
  shiv_restore_caller_env "$PACKAGE/mise.toml"
}

@test "env restore: empty and multiline snapshots round-trip without evaluation" {
  write_declaration '["MYAPP_EMPTY", "MYAPP_TEXT"]'
  export SHIV_CALLER_VALUE_6d79617070_MYAPP_EMPTY=''
  export SHIV_CALLER_VALUE_6d79617070_MYAPP_TEXT=$'line one\n$(touch forbidden) "quotes" \\ tail\n'
  export EXPECTED="$SHIV_CALLER_VALUE_6d79617070_MYAPP_TEXT"
  run restore
  [ "$status" -eq 0 ]
  exports="$output"
  eval "$exports"
  [ "$MYAPP_EMPTY" = '' ]
  [ "$MYAPP_TEXT" = "$EXPECTED" ]
  [ ! -e forbidden ]
}

@test "env restore: absent snapshots leave package defaults intact" {
  write_declaration '["MYAPP_PROVIDER"]'
  unset SHIV_CALLER_VALUE_6d79617070_MYAPP_PROVIDER
  export MYAPP_PROVIDER=package
  run restore
  [ "$status" -eq 0 ]
  [ "$output" = '' ]
  [ "$MYAPP_PROVIDER" = package ]
}

@test "env restore: empty declaration emits nothing" {
  write_declaration '[]'
  run restore
  [ "$status" -eq 0 ]
  [ "$output" = '' ]
}

@test "env restore: invalid declaration fails before emitting any export" {
  write_declaration '["MYAPP_PROVIDER", "not a variable"]'
  export SHIV_CALLER_VALUE_6d79617070_MYAPP_PROVIDER=fictional
  run restore
  [ "$status" -ne 0 ]
  [[ "$output" != *'export MYAPP_PROVIDER='* ]]
}

@test "env restore: missing or scalar declarations fail closed" {
  for declaration in '[other]' 'caller_env = "MYAPP_PROVIDER"'; do
    printf '[_.shiv]\n%s\n' "$declaration" > "$PACKAGE/mise.toml"
    run restore
    [ "$status" -ne 0 ]
    [[ "$output" != *'export MYAPP_PROVIDER='* ]]
  done
}

@test "env restore: relative config paths are refused" {
  source "$REPO_DIR/lib/env-restore.sh"
  run shiv_restore_caller_env mise.toml
  [ "$status" -ne 0 ]
  [[ "$output" = *'requires an absolute config path'* ]]
}

@test "env restore: reserved handoff and caller-directory names are refused" {
  for name in SHIV_CALLER_MYAPP_PROVIDER MYAPP_CALLER_PWD; do
    write_declaration "[\"$name\"]"
    run restore
    [ "$status" -ne 0 ]
  done
}

@test "env restore: malformed owner binding fails before emitting exports" {
  write_declaration '["MYAPP_PROVIDER"]'
  local directory_key
  directory_key=$(shiv_caller_env_key "$(cd "$PACKAGE" && pwd -P)")
  for owner in '6d7' 'not_hex'; do
    export "SHIV_CALLER_OWNER_$directory_key=$owner"
    run restore
    [ "$status" -ne 0 ]
    [[ "$output" = *'requires a generated-shim owner'* ]]
    [[ "$output" != *'export MYAPP_PROVIDER='* ]]
  done
}

@test "env restore: no directory owner refuses legacy or unrelated snapshots" {
  write_declaration '["MYAPP_PROVIDER"]'
  local directory_key
  directory_key=$(shiv_caller_env_key "$(cd "$PACKAGE" && pwd -P)")
  unset "SHIV_CALLER_OWNER_$directory_key"
  export SHIV_CALLER_MYAPP_PROVIDER='legacy caller'
  export SHIV_CALLER_VALUE_6f74686572_MYAPP_PROVIDER='other caller'
  run restore
  [ "$status" -ne 0 ]
  [[ "$output" = *'requires a generated-shim owner'* ]]
  [[ "$output" != *'export MYAPP_PROVIDER='* ]]
}

@test "env restore: optional absence recognizes only Mise's missing-key diagnostic" {
  source "$REPO_DIR/lib/env-restore.sh"
  export MISE_BIN="$BATS_TEST_TMPDIR/mise-read-failure"
  cat > "$MISE_BIN" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$READ_FAILURE" >&2
exit 1
SH
  chmod +x "$MISE_BIN"
  export READ_FAILURE="mise ERROR Key not found: _.shiv.caller_env in $PACKAGE/mise.toml"
  run shiv_read_caller_declaration "$PACKAGE/mise.toml" true
  [ "$status" -eq 0 ]
  [ "$output" = '[]' ]

  for READ_FAILURE in 'mise ERROR permission denied' 'mise ERROR invalid TOML' 'unexpected failure'; do
    export READ_FAILURE
    run shiv_read_caller_declaration "$PACKAGE/mise.toml" true
    [ "$status" -ne 0 ]
    [ "$output" = "$READ_FAILURE" ]
  done
}

prepare_real_shims() {
  source "$REPO_DIR/lib/shim.sh"
  export SHIV_BIN_DIR="$BATS_TEST_TMPDIR/bin"
  export SHIV_CACHE_DIR="$BATS_TEST_TMPDIR/cache"
  mkdir -p "$SHIV_BIN_DIR" "$SHIV_CACHE_DIR/tasks"
  shiv_create_shim shiv "$(cd "$REPO_DIR" && pwd)"
  export RESTORE_SHIV="$SHIV_BIN_DIR/shiv"
}

write_restore_hook() {
  cat > "$1/restore.sh" <<'SH'
#!/usr/bin/env bash
package_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd) || exit 1
exports=$("$RESTORE_SHIV" env restore "$package_dir/mise.toml") || exit 1
eval "$exports"
SH
}

@test "env restore: actual generated consumer shim and Mise hook restore only declared inputs" {
  cat > "$PACKAGE/mise.toml" <<'TOML'
[settings]
experimental = true
[env]
MYAPP_PROVIDER = "package"
MYAPP_UNDECLARED = "package untouched"
_.source = { path = "restore.sh", tools = true }
[_.shiv]
caller_env = ["MYAPP_PROVIDER", "MYAPP_EMPTY", "MYAPP_TEXT"]
[tasks.check]
run = '''
set -eu
test "$MYAPP_PROVIDER" = "fictional caller"
test "$MYAPP_UNDECLARED" = "package untouched"
test "${MYAPP_EMPTY+x}" = x
test "$MYAPP_EMPTY" = ""
test "$MYAPP_TEXT" = "$EXPECTED_TEXT"
'''
TOML
  prepare_real_shims
  write_restore_hook "$PACKAGE"
  shiv_create_shim myapp "$PACKAGE"
  export MYAPP_PROVIDER='fictional caller'
  export MYAPP_UNDECLARED='must not restore'
  export MYAPP_EMPTY=''
  export MYAPP_TEXT=$'fictional\n$(touch forbidden) "quoted" \\ trailing\n'
  export EXPECTED_TEXT="$MYAPP_TEXT"
  run mise trust "$PACKAGE/mise.toml"
  [ "$status" -eq 0 ]
  run "$SHIV_BIN_DIR/myapp" check
  [ "$status" -eq 0 ]
}

# The inner package deliberately hides the outer setting after taking its own
# snapshot. Restoring the outer config must still find the original caller.
run_nested_restore() {
  local outer_name="$1" inner_name="$2"
  local outer="$BATS_TEST_TMPDIR/outer" inner="$BATS_TEST_TMPDIR/inner"
  mkdir -p "$outer" "$inner"
  cat > "$outer/mise.toml" <<'TOML'
[settings]
experimental = true
[env]
MY_TOOL_PROVIDER = "outer default"
[_.shiv]
caller_env = ["MY_TOOL_PROVIDER"]
[tasks.check]
run = '"$INNER_SHIM" check'
TOML
  cat > "$inner/mise.toml" <<'TOML'
[settings]
experimental = true
[env]
MY_TOOL_PROVIDER = "inner default"
[_.shiv]
caller_env = ["MY_TOOL_PROVIDER"]
[tasks.check]
run = '''
set -eu
unset MY_TOOL_PROVIDER
exports=$("$RESTORE_SHIV" env restore "$OUTER_CONFIG")
eval "$exports"
test "$MY_TOOL_PROVIDER" = "original outer caller"
exports=$("$RESTORE_SHIV" env restore "$INNER_CONFIG")
eval "$exports"
test "$MY_TOOL_PROVIDER" = "original outer caller"
'''
TOML
  # Both configs declare the same setting; their generated shims must bind
  # different owners even when the sanitized setting namespaces overlap.
  prepare_real_shims
  shiv_create_shim "$outer_name" "$outer"
  shiv_create_shim "$inner_name" "$inner"
  export INNER_SHIM="$SHIV_BIN_DIR/$inner_name"
  export OUTER_CONFIG="$outer/mise.toml" INNER_CONFIG="$inner/mise.toml"
  export MY_TOOL_PROVIDER='original outer caller'
  run mise trust "$outer/mise.toml"
  [ "$status" -eq 0 ]
  run mise trust "$inner/mise.toml"
  [ "$status" -eq 0 ]
  run "$SHIV_BIN_DIR/$outer_name" check
  [ "$status" -eq 0 ]
}

@test "env restore: nested prefix package cannot replace the outer owner's value" {
  run_nested_restore my-tool my
}

@test "env restore: nested sanitized-name collision restores each exact owner" {
  run_nested_restore my-tool my_tool
}
