#!/usr/bin/env bats

load helpers

setup() {
  source "$REPO_DIR/lib/shim.sh"
  export TEST_HOME="$BATS_TEST_TMPDIR/restoration"
  export SHIV_BIN_DIR="$TEST_HOME/bin" SHIV_CACHE_DIR="$TEST_HOME/cache ' with \$ signs"
  export MISE_OFFLINE=true MISE_AUTO_INSTALL=false MISE_TASK_RUN_AUTO_INSTALL=false
  export PACKAGE="$TEST_HOME/package ' with \$ signs"
  mkdir -p "$PACKAGE" "$SHIV_BIN_DIR"
}

create_restoring_package() {
  cat > "$PACKAGE/mise.toml" <<'TOML'
[settings]
experimental = true
[env]
MYAPP_PROVIDER = "package provider"
MYAPP_EMPTY = "package nonempty"
MYAPP_TEXT = "package text"
MYAPP_ABSENT = "package absent"
MYAPP_UNDECLARED = "package undeclared"
[_.shiv]
caller_env = ["MYAPP_PROVIDER", "MYAPP_EMPTY", "MYAPP_TEXT", "MYAPP_ABSENT"]
[tasks.check]
run = '''
set -eu
test "$MYAPP_PROVIDER" = "$EXPECTED_PROVIDER"
test "$MYAPP_EMPTY" = "$EXPECTED_EMPTY"
test "$MYAPP_TEXT" = "$EXPECTED_TEXT"
test "$MYAPP_ABSENT" = "package absent"
test "$MYAPP_UNDECLARED" = "package undeclared"
test ! -e forbidden
printf 'RESTORED\n'
'''
TOML
  export MYAPP_PROVIDER='fictional caller' MYAPP_EMPTY=''
  export MYAPP_TEXT=$'line one\n$(touch forbidden) "quotes" \\ tail\n'
  export MYAPP_UNDECLARED='must not restore'
  export EXPECTED_PROVIDER="$MYAPP_PROVIDER" EXPECTED_EMPTY="$MYAPP_EMPTY" EXPECTED_TEXT="$MYAPP_TEXT"
  unset MYAPP_ABSENT
  mise trust "$PACKAGE/mise.toml"
  shiv_create_shim myapp "$PACKAGE"
}

@test "generated restoration: declarations alone restore exact caller values" {
  create_restoring_package
  run "$SHIV_BIN_DIR/myapp" check
  [ "$status" -eq 0 ]
  [[ "$output" = *RESTORED* ]]
  # No maintained package hook or Shiv executable is available to restoration.
  [ ! -e "$PACKAGE/restore.sh" ]
  [ ! -e "$SHIV_BIN_DIR/shiv" ]
  run grep -R -F 'fictional caller' "$SHIV_CACHE_DIR/shim-env"
  [ "$status" -eq 1 ]
}

@test "generated restoration: caller Mise diff does not erase declared settings" {
  create_restoring_package
  mkdir -p "$TEST_HOME/caller"
  printf '[env]\nMYAPP_PROVIDER = "Mise caller"\n' > "$TEST_HOME/caller/mise.toml"
  mise trust "$TEST_HOME/caller/mise.toml"
  export TARGET_SHIM="$SHIV_BIN_DIR/myapp" EXPECTED_PROVIDER='Mise caller'
  run mise -C "$TEST_HOME/caller" exec --no-deps -- bash -c \
    'test -n "${__MISE_DIFF-}" && exec "$TARGET_SHIM" check'
  [ "$status" -eq 0 ]
  [[ "$output" = *RESTORED* ]]
}

# These precedence checks cover inline tasks, not executable tasks or mise exec.
# The task-dependent behavior is documented in docs/caller-environment.md.
@test "generated restoration: explicit local overrides win for inline tasks" {
  create_restoring_package
  cat > "$PACKAGE/mise.local.toml" <<'TOML'
[env]
MYAPP_PROVIDER = "local provider"
MYAPP_EMPTY = "local nonempty"
MYAPP_TEXT = "local text"
TOML
  mise trust "$PACKAGE/mise.local.toml"
  export EXPECTED_PROVIDER='local provider' EXPECTED_EMPTY='local nonempty' EXPECTED_TEXT='local text'
  run "$SHIV_BIN_DIR/myapp" check
  [ "$status" -eq 0 ]
  [[ "$output" = *RESTORED* ]]
}

@test "generated restoration: local source hooks override caller settings for inline tasks" {
  create_restoring_package
  printf 'export MYAPP_PROVIDER="local source"\n' > "$PACKAGE/local-source.sh"
  printf '[env]\n_.source = "local-source.sh"\n' > "$PACKAGE/mise.local.toml"
  mise trust "$PACKAGE/mise.local.toml"
  export EXPECTED_PROVIDER='local source'
  run "$SHIV_BIN_DIR/myapp" check
  [ "$status" -eq 0 ]
  [[ "$output" = *RESTORED* ]]
}

@test "generated restoration: nested config layout uses the package owner" {
  create_restoring_package
  mkdir -p "$PACKAGE/.mise"
  mv "$PACKAGE/mise.toml" "$PACKAGE/.mise/config.toml"
  mise trust "$PACKAGE/.mise/config.toml"
  shiv_create_shim myapp "$PACKAGE"
  run "$SHIV_BIN_DIR/myapp" check
  [ "$status" -eq 0 ]
  [[ "$output" = *RESTORED* ]]
}

@test "generated restoration: artifacts are private read-only source with no caller values" {
  create_restoring_package
  run find "$SHIV_CACHE_DIR/shim-env" -type f ! -perm 0400
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  run find "$SHIV_CACHE_DIR/shim-env" -type d ! -perm 0700
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  run grep -R -F '$(touch forbidden)' "$SHIV_CACHE_DIR/shim-env"
  [ "$status" -eq 1 ]
}

@test "generated restoration: ambiguous trusted-path separators preserve the old shim" {
  create_restoring_package
  cp "$SHIV_BIN_DIR/myapp" "$TEST_HOME/old-shim"
  SHIV_CACHE_DIR="$TEST_HOME/ambiguous:path"
  run shiv_create_shim myapp "$PACKAGE"
  [ "$status" -ne 0 ]
  [[ "$output" = *'cannot contain a colon'* ]]
  cmp "$TEST_HOME/old-shim" "$SHIV_BIN_DIR/myapp"
}

@test "generated restoration: no declaration leaves defaults and existing source intact" {
  cat > "$PACKAGE/source.sh" <<'SH'
export MYAPP_SOURCE='package source'
SH
  cat > "$PACKAGE/mise.toml" <<'TOML'
[env]
MYAPP_PROVIDER = "default"
_.source = "source.sh"
[tasks.check]
run = 'test "$MYAPP_PROVIDER" = default && test "$MYAPP_SOURCE" = "package source"'
TOML
  mise trust "$PACKAGE/mise.toml"
  shiv_create_shim myapp "$PACKAGE"
  export MYAPP_PROVIDER='caller'
  run "$SHIV_BIN_DIR/myapp" check
  [ "$status" -eq 0 ]
}

@test "generated restoration: declaration composes with an existing package source" {
  create_restoring_package
  printf 'export MYAPP_SOURCE="package source"\nexport MYAPP_PROVIDER="source provider"\n' > "$PACKAGE/source.sh"
  sed -i.bak '/\[env\]/a\
_.source = "source.sh"\
' "$PACKAGE/mise.toml"
  sed -i.bak '/test ! -e forbidden/a\
test "$MYAPP_SOURCE" = "package source"\
' "$PACKAGE/mise.toml"
  mise trust "$PACKAGE/mise.toml"
  run "$SHIV_BIN_DIR/myapp" check
  [ "$status" -eq 0 ]
  [[ "$output" = *RESTORED* ]]
}

@test "generated restoration: malformed declaration fails rather than falling back" {
  create_restoring_package
  printf '\n' >> "$PACKAGE/mise.toml"
  # Read the current declaration, not an install-time copy.
  sed -i.bak 's/caller_env = .*/caller_env = "MYAPP_PROVIDER"/' "$PACKAGE/mise.toml"
  mise trust "$PACKAGE/mise.toml"
  run "$SHIV_BIN_DIR/myapp" check
  [ "$status" -ne 0 ]
  [[ "$output" = *'caller_env must be an array'* ]]
  [[ "$output" != *RESTORED* ]]
}

@test "generated restoration: invalid TOML is not an absent declaration" {
  create_restoring_package
  printf 'invalid = [\n' >> "$PACKAGE/mise.toml"
  run "$SHIV_BIN_DIR/myapp" check
  [ "$status" -ne 0 ]
  [[ "$output" != *RESTORED* ]]
}

@test "generated restoration: missing config fails before package tasks run" {
  create_restoring_package
  local config
  config=$(find "$SHIV_CACHE_DIR/shim-env" -name restore.toml)
  rm "$config"
  run "$SHIV_BIN_DIR/myapp" check
  [ "$status" -ne 0 ]
  [[ "$output" = *'regenerate the shim'* ]]
  [[ "$output" != *RESTORED* ]]
}

@test "generated restoration: missing helper fails before package tasks run" {
  create_restoring_package
  local helper
  helper=$(find "$SHIV_CACHE_DIR/shim-env" -name restore.sh)
  rm "$helper"
  run "$SHIV_BIN_DIR/myapp" check
  [ "$status" -ne 0 ]
  [[ "$output" = *'regenerate the shim'* ]]
  [[ "$output" != *RESTORED* ]]
}

@test "generated restoration: regeneration preserves artifacts used by an older shim" {
  create_restoring_package
  cp "$SHIV_BIN_DIR/myapp" "$SHIV_BIN_DIR/old-myapp"
  shiv_create_shim myapp "$PACKAGE"
  run "$SHIV_BIN_DIR/old-myapp" check
  [ "$status" -eq 0 ]
  [[ "$output" = *RESTORED* ]]
  run "$SHIV_BIN_DIR/myapp" check
  [ "$status" -eq 0 ]
  [[ "$output" = *RESTORED* ]]
  local config
  config=$(find "$SHIV_CACHE_DIR/shim-env" -name restore.toml | wc -l)
  [ "$config" -eq 2 ]
}

@test "generated restoration: paranoid trust covers only the generated file" {
  create_restoring_package
  export MISE_PARANOID=true
  # Mise run normally auto-trusts its active package configs. Paranoid mode
  # disables that behavior, making this a test of the shim's narrow trust grant.
  mise trust "$PACKAGE/mise.toml"
  run "$SHIV_BIN_DIR/myapp" check
  [ "$status" -eq 0 ]
  [[ "$output" = *RESTORED* ]]
  printf '[env]\n_.source = "forbidden-source.sh"\n' > "$PACKAGE/mise.local.toml"
  printf 'touch forbidden\n' > "$PACKAGE/forbidden-source.sh"
  run "$SHIV_BIN_DIR/myapp" check
  [ "$status" -ne 0 ]
  [ ! -e "$PACKAGE/forbidden" ]
}

run_generated_nested() {
  local inner_name="$1" outer="$TEST_HOME/outer" inner="$TEST_HOME/inner"
  mkdir -p "$outer" "$inner"
  cat > "$outer/mise.toml" <<'TOML'
[env]
MY_TOOL_PROVIDER = "outer default"
MY_TOOL_INNER = "outer setting"
[_.shiv]
caller_env = ["MY_TOOL_PROVIDER"]
[tasks.check]
run = 'test "$MY_TOOL_PROVIDER" = "original caller" && "$INNER_SHIM" check'
TOML
  cat > "$inner/mise.toml" <<'TOML'
[env]
MY_TOOL_PROVIDER = "inner default"
MY_TOOL_INNER = "inner default"
[_.shiv]
caller_env = ["MY_TOOL_INNER"]
[tasks.check]
run = 'test "$MY_TOOL_PROVIDER" = "inner default" && test "$MY_TOOL_INNER" = "outer setting"'
TOML
  mise trust "$outer/mise.toml"
  mise trust "$inner/mise.toml"
  shiv_create_shim my-tool "$outer"
  shiv_create_shim "$inner_name" "$inner"
  export MY_TOOL_PROVIDER='original caller' INNER_SHIM="$SHIV_BIN_DIR/$inner_name"
  run "$SHIV_BIN_DIR/my-tool" check
  [ "$status" -eq 0 ]
}

@test "generated restoration: nested prefix package selects its own declaration" {
  run_generated_nested my
}

@test "generated restoration: nested sanitized-name collision selects its own declaration" {
  run_generated_nested my_tool
}

@test "generated restoration: shim selects its own config instead of inherited default" {
  create_restoring_package
  printf '[env]\nMYAPP_PROVIDER = "unrelated"\n' > "$TEST_HOME/unrelated.toml"
  export MISE_DEFAULT_CONFIG_FILENAME="$TEST_HOME/unrelated.toml"
  export MISE_OVERRIDE_CONFIG_FILENAMES="$TEST_HOME/unrelated.toml"
  run "$SHIV_BIN_DIR/myapp" check
  [ "$status" -eq 0 ]
  [[ "$output" = *RESTORED* ]]
}
