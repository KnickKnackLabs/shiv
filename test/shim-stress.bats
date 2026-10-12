#!/usr/bin/env bats
# Deterministic generated-shim stress matrix for artifact and runtime boundaries.

REPO_DIR="$BATS_TEST_DIRNAME/.."
load helpers

setup() {
  source "$REPO_DIR/lib/shim.sh"

  export STRESS_ROOT="$BATS_TEST_TMPDIR/generated-shim-stress"
  mkdir -p "$STRESS_ROOT"
}

create_stress_repo() {
  local repo_dir="$1" marker="$2" task_path="${3:-stress/write}"

  mkdir -p "$(dirname "$repo_dir/.mise/tasks/$task_path")"
  printf '[tools]\n' > "$repo_dir/mise.toml"
  cat > "$repo_dir/.mise/tasks/$task_path" <<TASK
#!/usr/bin/env bash
set -euo pipefail
: "\${STRESS_OUTPUT:?STRESS_OUTPUT is required}"
mkdir -p "\$(dirname "\$STRESS_OUTPUT")"
printf '%s\n' '$marker' > "\$STRESS_OUTPUT"
printf 'STRESS_OK:%s\n' '$marker'
TASK
  chmod +x "$repo_dir/.mise/tasks/$task_path"
  mise trust "$repo_dir/mise.toml" >/dev/null 2>&1
}

create_conflicting_override() {
  local config="$1"

  mkdir -p "$(dirname "$config")"
  cat > "$config" <<'TOML'
[tasks."stress:write"]
run = "printf 'OVERRIDE_RAN\\n'"
TOML
  mise trust "$config" >/dev/null 2>&1
}

generate_stress_shim() {
  local name="$1" repo_dir="$2" bin_dir="$3" cache_dir="$4"

  SHIV_BIN_DIR="$bin_dir" SHIV_CACHE_DIR="$cache_dir" \
    shiv_create_shim "$name" "$repo_dir"
}

populate_stress_task_map() {
  local name="$1" repo_dir="$2" cache_dir="$3"

  SHIV_CACHE_DIR="$cache_dir" SHIV_SKIP_CACHE= \
    shiv_cache_task_map "$name" "$repo_dir"
}

set_stress_context() {
  STRESS_CASE="$1"
  STRESS_REPO="$2"
  STRESS_SHIM="$3"
  STRESS_TASK_MAP="$4"
  STRESS_RUNTIME_XDG="$5"
  STRESS_INVOCATION=""
}

shell_join() {
  local argument joined=""

  for argument in "$@"; do
    joined="$joined$(printf '%q' "$argument") "
  done
  printf '%s' "$joined"
}

report_stress_failure() {
  local reason="$1" captured_output="${2:-}"

  {
    printf '\nGenerated-shim stress failure\n'
    printf 'case=%s\n' "$STRESS_CASE"
    printf 'reason=%s\n' "$reason"
    printf 'repo=%s\n' "$STRESS_REPO"
    printf 'shim=%s\n' "$STRESS_SHIM"
    printf 'task_map=%s\n' "$STRESS_TASK_MAP"
    printf 'runtime_xdg=%s\n' "$STRESS_RUNTIME_XDG"
    printf 'invocation=%s\n' "$STRESS_INVOCATION"
    printf 'bash=%s\n' "${BASH_VERSION:-unknown}"
    printf 'mise=%s\n' "$(mise --version 2>&1)"
    if [ -n "$captured_output" ]; then
      printf '%s\n' '--- captured output ---'
      printf '%s\n' "$captured_output"
    fi
    if [ -f "$STRESS_TASK_MAP" ]; then
      printf '%s\n' '--- generation task map ---'
      cat "$STRESS_TASK_MAP"
    fi
    if [ -d "$STRESS_RUNTIME_XDG" ]; then
      printf '%s\n' '--- runtime XDG files ---'
      find "$STRESS_RUNTIME_XDG" -type f -print -exec sh -c 'printf "contents: "; cat "$1"' _ {} \;
    fi
    if [ -f "$STRESS_SHIM" ]; then
      printf '%s\n' '--- generated shim ---'
      cat "$STRESS_SHIM"
    fi
    printf '%s\n' '--- end stress failure ---'
  } >&3
}

assert_stress_syntax() {
  if ! bash -n "$STRESS_SHIM"; then
    report_stress_failure "generated shim failed bash -n"
    return 1
  fi
}

assert_stress_execution() {
  local expected_marker="$1" output_file="$2"
  shift 2

  STRESS_INVOCATION=$(shell_join "$@")
  run "$@"
  if [ "$status" -ne 0 ]; then
    report_stress_failure "generated shim exited $status" "$output"
    return 1
  fi
  if [[ "$output" != *"STRESS_OK:$expected_marker"* ]]; then
    report_stress_failure "generated shim returned unexpected output" "$output"
    return 1
  fi
  if [ ! -f "$output_file" ]; then
    report_stress_failure "nested task did not create $output_file" "$output"
    return 1
  fi
  if [ "$(cat "$output_file")" != "$expected_marker" ]; then
    report_stress_failure "nested task wrote the wrong marker" "$output"
    return 1
  fi
}

assert_file_contents() {
  local path="$1" expected="$2" reason="$3"

  if [ ! -f "$path" ] || [ "$(cat "$path")" != "$expected" ]; then
    report_stress_failure "$reason"
    return 1
  fi
}

@test "shim stress: hostile artifact paths stay literal with a populated cache" {
  local case_root="$STRESS_ROOT/hostile-populated"
  local repo_dir="$case_root/repos/nested path/quote's/package"
  local artifact_root="$case_root/artifacts/nested path/quote's/\$cash/\`tick\`"
  local bin_dir="$artifact_root/bin" cache_dir="$artifact_root/cache"
  local runtime_xdg="$case_root/runtime cache" override="$case_root/override.toml"
  local shim="$bin_dir/stress-tool" task_map="$cache_dir/tasks/stress-tool"
  local runtime_map="$runtime_xdg/shiv/tasks/stress-tool"
  local output_file="$artifact_root/results/hostile.txt"

  create_stress_repo "$repo_dir" "hostile-populated"
  create_conflicting_override "$override"
  generate_stress_shim "stress-tool" "$repo_dir" "$bin_dir" "$cache_dir"
  populate_stress_task_map "stress-tool" "$repo_dir" "$cache_dir"
  mkdir -p "$(dirname "$runtime_map")"
  printf 'conflicting task\n' > "$runtime_map"

  set_stress_context "hostile-populated" "$repo_dir" "$shim" "$task_map" "$runtime_xdg"
  assert_stress_syntax
  assert_stress_execution "hostile-populated" "$output_file" \
    env XDG_CACHE_HOME="$runtime_xdg" \
      MISE_OVERRIDE_CONFIG_FILENAMES="$override" \
      STRESS_OUTPUT="$output_file" \
      "$shim" stress write

  assert_file_contents "$task_map" "stress write" \
    "populated generation-time task map changed"
  assert_file_contents "$runtime_map" "conflicting task" \
    "runtime XDG task map was changed or consumed"
}

@test "shim stress: a cache miss regenerates only the generation-time map" {
  local case_root="$STRESS_ROOT/cache-miss"
  local repo_dir="$case_root/repos/nested package"
  local artifact_root="$case_root/generated/\$cache/\`literal\`"
  local bin_dir="$artifact_root/bin" cache_dir="$artifact_root/cache"
  local runtime_xdg="$case_root/runtime-xdg" override="$case_root/override.toml"
  local shim="$bin_dir/stress-tool" task_map="$cache_dir/tasks/stress-tool"
  local runtime_map="$runtime_xdg/shiv/tasks/stress-tool"
  local output_file="$artifact_root/results/cache-miss.txt"

  create_stress_repo "$repo_dir" "cache-miss"
  create_conflicting_override "$override"
  generate_stress_shim "stress-tool" "$repo_dir" "$bin_dir" "$cache_dir"
  mkdir -p "$(dirname "$runtime_map")"
  printf 'conflicting task\n' > "$runtime_map"
  [ ! -e "$task_map" ]

  set_stress_context "cache-miss" "$repo_dir" "$shim" "$task_map" "$runtime_xdg"
  assert_stress_syntax
  assert_stress_execution "cache-miss" "$output_file" \
    env -u SHIV_SKIP_CACHE \
      XDG_CACHE_HOME="$runtime_xdg" \
      MISE_OVERRIDE_CONFIG_FILENAMES="$override" \
      STRESS_OUTPUT="$output_file" \
      "$shim" stress write

  assert_file_contents "$task_map" "stress write" \
    "cache miss did not create the generation-time task map"
  assert_file_contents "$runtime_map" "conflicting task" \
    "cache miss wrote into the runtime XDG cache"
  [ ! -e "$task_map.tmp" ] || {
    report_stress_failure "cache miss left a temporary task map"
    return 1
  }
}

@test "shim stress: same-name package versions keep artifacts and writes isolated" {
  local case_root="$STRESS_ROOT/same-name-versions"
  local first_repo="$case_root/packages/version one/stress-tool"
  local second_repo="$case_root/packages/version two/quote's/stress-tool"
  local first_root="$case_root/installs/one/\$artifacts"
  local second_root="$case_root/installs/two/\`artifacts\`"
  local first_bin="$first_root/bin" first_cache="$first_root/cache"
  local second_bin="$second_root/bin" second_cache="$second_root/cache"
  local first_shim="$first_bin/stress-tool" second_shim="$second_bin/stress-tool"
  local first_map="$first_cache/tasks/stress-tool" second_map="$second_cache/tasks/stress-tool"
  local first_output="$first_root/results/version.txt" second_output="$second_root/results/version.txt"
  local runtime_xdg="$case_root/runtime-xdg"
  local runtime_map="$runtime_xdg/shiv/tasks/stress-tool"
  local override="$case_root/override.toml"

  create_stress_repo "$first_repo" "version-one" "stress/version-one/write"
  create_stress_repo "$second_repo" "version-two" "stress/version-two/write"
  create_conflicting_override "$override"
  generate_stress_shim "stress-tool" "$first_repo" "$first_bin" "$first_cache"
  generate_stress_shim "stress-tool" "$second_repo" "$second_bin" "$second_cache"
  populate_stress_task_map "stress-tool" "$first_repo" "$first_cache"
  populate_stress_task_map "stress-tool" "$second_repo" "$second_cache"
  mkdir -p "$(dirname "$runtime_map")"
  printf 'conflicting task\n' > "$runtime_map"

  set_stress_context "same-name-version-one" "$first_repo" "$first_shim" "$first_map" "$runtime_xdg"
  assert_stress_syntax
  assert_stress_execution "version-one" "$first_output" \
    env XDG_CACHE_HOME="$runtime_xdg" \
      MISE_OVERRIDE_CONFIG_FILENAMES="$override" \
      STRESS_OUTPUT="$first_output" \
      "$first_shim" stress version-one write
  [ ! -e "$second_output" ] || {
    report_stress_failure "version one wrote into version two's artifact root"
    return 1
  }

  set_stress_context "same-name-version-two" "$second_repo" "$second_shim" "$second_map" "$runtime_xdg"
  assert_stress_syntax
  assert_stress_execution "version-two" "$second_output" \
    env XDG_CACHE_HOME="$runtime_xdg" \
      MISE_OVERRIDE_CONFIG_FILENAMES="$override" \
      STRESS_OUTPUT="$second_output" \
      "$second_shim" stress version-two write

  assert_file_contents "$first_output" "version-one" \
    "version two changed version one's output"
  assert_file_contents "$second_output" "version-two" \
    "version two wrote the wrong output"
  assert_file_contents "$first_map" "stress version-one write" \
    "version one's task map changed"
  assert_file_contents "$second_map" "stress version-two write" \
    "version two's task map changed"
  assert_file_contents "$runtime_map" "conflicting task" \
    "same-name versions changed the runtime XDG map"
}
