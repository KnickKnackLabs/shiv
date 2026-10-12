#!/usr/bin/env bats

load helpers

# Exercise assembly faults in private source copies, never the installed shim.
assert_assembly_preserves_shim() {
  local failure="$1" caller_mode="$2" fragment

  for fragment in shim-runtime/package-tasks.sh shim-runtime/dispatch.sh caller-env.sh env-restore.sh; do
    local fixture="$TEST_HOME/assembly-$failure-$caller_mode-$fragment"
    mkdir -p "$fixture/bin" "$fixture/package"
    cp -R "$REPO_DIR/lib" "$fixture/lib"
    printf '#!/usr/bin/env bash\nprintf "ORIGINAL_SHIM\\n"\n' > "$fixture/bin/myapp"
    chmod +x "$fixture/bin/myapp"
    cp "$fixture/bin/myapp" "$fixture/original"

    local source_file="$fixture/lib/$fragment"
    if [ "$failure" = missing ]; then
      rm "$source_file"
    fi

    run env ASSEMBLY_FIXTURE="$fixture" ASSEMBLY_FAILURE="$failure" \
      ASSEMBLY_SOURCE="$source_file" ASSEMBLY_CALLER="$caller_mode" bash -c '
      source "$ASSEMBLY_FIXTURE/lib/shim.sh"
      SHIV_BIN_DIR="$ASSEMBLY_FIXTURE/bin"
      SHIV_CACHE_DIR="$ASSEMBLY_FIXTURE/cache"

      # Inject a partial read failure even when permission tests would be unreliable.
      sed() {
        if [ "$ASSEMBLY_FAILURE" = read ] && [ "$2" = "$ASSEMBLY_SOURCE" ]; then
          printf "PARTIAL_FRAGMENT\n"
          return 7
        fi
        command sed "$@"
      }

      if [ "$ASSEMBLY_CALLER" = strict ]; then
        set -eu
        shiv_create_shim myapp "$ASSEMBLY_FIXTURE/package"
      else
        if shiv_create_shim myapp "$ASSEMBLY_FIXTURE/package"; then
          exit 0
        else
          exit 1
        fi
      fi
    '
    [ "$status" -ne 0 ]
    cmp "$fixture/original" "$fixture/bin/myapp"
    [ -x "$fixture/bin/myapp" ]

    run "$fixture/bin/myapp"
    [ "$status" -eq 0 ]
    [ "$output" = ORIGINAL_SHIM ]

    run find "$fixture/bin" -name '.myapp.*'
    [ "$status" -eq 0 ]
    [ -z "$output" ]

    if [ -d "$fixture/cache/shim-env" ]; then
      run find "$fixture/cache/shim-env" -mindepth 1
      [ "$status" -eq 0 ]
      [ -z "$output" ]
    fi
  done
}

@test "shim: missing fragments preserve existing shim under conditional generation" {
  assert_assembly_preserves_shim missing conditional
}

@test "shim: missing fragments preserve existing shim under strict generation" {
  assert_assembly_preserves_shim missing strict
}

@test "shim: partial fragment read failure preserves existing shim under conditional generation" {
  assert_assembly_preserves_shim read conditional
}

@test "shim: partial fragment read failure preserves existing shim under strict generation" {
  assert_assembly_preserves_shim read strict
}

@test "shim: generated configuration selects package-specific caller assignment" {
  local repo_dir
  repo_dir=$(create_caller_repo "myapp")
  shiv install myapp "$repo_dir" 2>/dev/null

  grep -q "SHIV_CALLER_PWD_VAR='MYAPP_CALLER_PWD'" "$SHIV_BIN_DIR/myapp"
  grep -q 'export "$SHIV_CALLER_PWD_VAR=$PWD"' "$SHIV_BIN_DIR/myapp"
  ! grep -q 'export CALLER_PWD=' "$SHIV_BIN_DIR/myapp"
}

@test "shim: generated runtime survives removal of its source templates" {
  local repo_dir generator_lib
  repo_dir=$(create_caller_repo "myapp")
  generator_lib="$TEST_HOME/generator-lib"
  cp -R "$REPO_LIB_DIR" "$generator_lib"

  REPO_LIB_DIR="$generator_lib" shiv_create_shim "myapp" "$repo_dir"
  rm -rf "$generator_lib"

  run bash -c 'cd /tmp && "$1" show-caller' _ "$SHIV_BIN_DIR/myapp"
  [ "$status" -eq 0 ]
  [[ "$output" == *"/tmp"* ]]
}

@test "shim: install-time configuration preserves literal shell characters in repo paths" {
  local repo_dir
  repo_dir=$(create_caller_repo "quoted ' repo \$literal")
  shiv_create_shim "myapp" "$repo_dir"

  run bash -c 'cd /tmp && "$1" show-caller' _ "$SHIV_BIN_DIR/myapp"
  [ "$status" -eq 0 ]
  [[ "$output" == *"/tmp"* ]]
}
