#!/usr/bin/env bats
# Fictional-only restore checks, including the actual Mise source boundary.
REPO_DIR="$BATS_TEST_DIRNAME/.."
load helpers

setup() {
  export PACKAGE="$BATS_TEST_TMPDIR/package with spaces"
  mkdir -p "$PACKAGE"
  export MISE_AUTO_INSTALL=false MISE_TASK_RUN_AUTO_INSTALL=false MISE_OFFLINE=true
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
  export SHIV_CALLER_MYAPP_EMPTY=''
  export SHIV_CALLER_MYAPP_TEXT=$'line one\n$(touch forbidden) "quotes" \\ tail\n'
  export EXPECTED="$SHIV_CALLER_MYAPP_TEXT"
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
  unset SHIV_CALLER_MYAPP_PROVIDER
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
  export SHIV_CALLER_MYAPP_PROVIDER=fictional
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

@test "env restore: actual Mise source hook restores only declared fictional inputs" {
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
run = 'test "$MYAPP_PROVIDER" = "fictional caller" && test "$MYAPP_UNDECLARED" = "package untouched" && test "${MYAPP_EMPTY+x}" = x && test "$MYAPP_EMPTY" = "" && test "$MYAPP_TEXT" = "$EXPECTED_TEXT"'
TOML
  cat > "$PACKAGE/restore.sh" <<'SH'
#!/usr/bin/env bash
package_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd) || exit 1
exports=$("$RESTORE_SHIV" env restore "$package_dir/mise.toml") || exit 1
eval "$exports"
SH
  source "$REPO_DIR/lib/shim.sh"
  export SHIV_BIN_DIR="$BATS_TEST_TMPDIR/bin"
  export SHIV_CACHE_DIR="$BATS_TEST_TMPDIR/cache"
  mkdir -p "$SHIV_BIN_DIR" "$SHIV_CACHE_DIR/tasks"
  shiv_create_shim shiv "$(cd "$REPO_DIR" && pwd)"
  export RESTORE_SHIV="$SHIV_BIN_DIR/shiv"
  export SHIV_CALLER_MYAPP_PROVIDER='fictional caller'
  export SHIV_CALLER_MYAPP_UNDECLARED='must not restore'
  export SHIV_CALLER_MYAPP_EMPTY=''
  export SHIV_CALLER_MYAPP_TEXT=$'fictional\n$(touch forbidden) "quoted" \\ trailing\n'
  export EXPECTED_TEXT="$SHIV_CALLER_MYAPP_TEXT"
  run mise trust "$PACKAGE/mise.toml"
  [ "$status" -eq 0 ]
  run mise -C "$PACKAGE" run --skip-tools --skip-deps check
  [ "$status" -eq 0 ]
}
