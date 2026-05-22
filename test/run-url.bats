#!/usr/bin/env bats
# shiv run-url test suite

REPO_DIR="$BATS_TEST_DIRNAME/.."
export REPO_DIR
load helpers

setup() {
  export TEST_HOME="$BATS_TEST_TMPDIR/shiv"
  mkdir -p "$TEST_HOME"

  export SHIV_CACHE_DIR="$TEST_HOME/.cache/shiv"
  export SHIV_BIN_DIR="$TEST_HOME/.local/bin"
  export SHIV_DATA_DIR="$TEST_HOME/.local/share/shiv"
  export SHIV_CONFIG_DIR="$TEST_HOME/.config/shiv"
  export SHIV_REGISTRY="$SHIV_CONFIG_DIR/registry.json"

  mkdir -p "$SHIV_CACHE_DIR" "$SHIV_BIN_DIR"
  setup_shiv_on_path

  export PINNED_URL="https://raw.githubusercontent.com/owner/repo/0123456789abcdef0123456789abcdef01234567/task.py"
  export FLOATING_URL="https://raw.githubusercontent.com/owner/repo/main/task.py"
  export GIST_URL="https://gist.githubusercontent.com/owner/abcdef123456/raw/0123456789abcdef0123456789abcdef01234567/task.py"
  export CURL_LOG="$TEST_HOME/curl.log"
  touch "$CURL_LOG"
}

set_sucker_fixture() {
  export SUCKER_FIXTURE="$1"
}

write_args_sucker() {
  local path="$1"
  cat > "$path" <<'PY'
#!/usr/bin/env -S uv run --script
import os
import sys

print("CWD=" + os.getcwd())
print("CALLER=" + os.environ.get("SUCKER_CALLER_PWD", ""))
print("SOURCE=" + os.environ.get("SUCKER_SOURCE_URL", ""))
print("CACHE=" + os.environ.get("SUCKER_CACHE_PATH", ""))
print("ARGS=" + "|".join(sys.argv[1:]))
PY
}

write_print_sucker() {
  local path="$1" message="$2"
  cat > "$path" <<PY
#!/usr/bin/env -S uv run --script
print("$message")
PY
}

write_exit_sucker() {
  local path="$1"
  cat > "$path" <<'PY'
#!/usr/bin/env -S uv run --script
import sys

print("before exit")
print("exit stderr", file=sys.stderr)
sys.exit(7)
PY
}

install_mock_curl() {
  local mock="$BATS_TEST_TMPDIR/curl"
  cat > "$mock" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
out=""
url=""
while [ $# -gt 0 ]; do
  case "$1" in
    -o)
      out="$2"
      shift 2
      ;;
    -*)
      shift
      ;;
    *)
      url="$1"
      shift
      ;;
  esac
done
printf '%s\n' "$url" >> "$CURL_LOG"
if [ "${CURL_FAIL:-}" = "1" ]; then
  echo "mock curl failure" >&2
  exit 22
fi
if [ -z "$out" ]; then
  echo "mock curl missing -o" >&2
  exit 2
fi
cp "$SUCKER_FIXTURE" "$out"
MOCK
  chmod +x "$mock"
  export CURL="$mock"
}

@test "run-url: refuses floating GitHub raw URLs by default" {
  set_sucker_fixture "$TEST_HOME/sucker.py"
  write_print_sucker "$SUCKER_FIXTURE" "unused"
  install_mock_curl

  run shiv run-url "$FLOATING_URL"
  [ "$status" -eq 1 ]
  [[ "$output" == *"refusing floating"* ]]
  [ ! -s "$CURL_LOG" ]
}

@test "run-url: --floating makes floating URL execution explicit" {
  set_sucker_fixture "$TEST_HOME/sucker.py"
  write_print_sucker "$SUCKER_FIXTURE" "floating-ok"
  install_mock_curl

  run shiv run-url --floating "$FLOATING_URL"
  [ "$status" -eq 0 ]
  [[ "$output" == *"floating-ok"* ]]
  grep -qxF "$FLOATING_URL" "$CURL_LOG"
}

@test "run-url: runs pinned uv script with args in caller cwd" {
  local caller="$TEST_HOME/workspace" caller_real
  mkdir -p "$caller"
  caller_real=$(cd "$caller" && pwd -P)
  set_sucker_fixture "$TEST_HOME/sucker.py"
  write_args_sucker "$SUCKER_FIXTURE"
  install_mock_curl

  run bash -c "cd '$caller' && shiv run-url '$PINNED_URL' alpha 'two words' --flag"
  [ "$status" -eq 0 ]
  [[ "$output" == *"CWD=$caller_real"* ]]
  [[ "$output" == *"CALLER=$caller"* ]]
  [[ "$output" == *"SOURCE=$PINNED_URL"* ]]
  [[ "$output" == *"ARGS=alpha|two words|--flag"* ]]
}

@test "run-url: accepts pinned gist raw URLs" {
  set_sucker_fixture "$TEST_HOME/sucker.py"
  write_print_sucker "$SUCKER_FIXTURE" "gist-ok"
  install_mock_curl

  run shiv run-url "$GIST_URL"
  [ "$status" -eq 0 ]
  [[ "$output" == *"gist-ok"* ]]
  grep -qxF "$GIST_URL" "$CURL_LOG"
}

@test "run-url: caches pinned URLs by URL and content hash" {
  set_sucker_fixture "$TEST_HOME/sucker.py"
  write_print_sucker "$SUCKER_FIXTURE" "cached-v1"
  install_mock_curl

  run shiv run-url "$PINNED_URL"
  [ "$status" -eq 0 ]
  [[ "$output" == *"cached-v1"* ]]

  write_print_sucker "$SUCKER_FIXTURE" "cached-v2"
  export CURL_FAIL=1
  run shiv run-url "$PINNED_URL"
  [ "$status" -eq 0 ]
  [[ "$output" == *"cached-v1"* ]]
  [[ "$output" != *"cached-v2"* ]]
  [ "$(wc -l < "$CURL_LOG" | tr -d ' ')" -eq 1 ]
}

@test "run-url: floating URLs download every time" {
  set_sucker_fixture "$TEST_HOME/sucker.py"
  write_print_sucker "$SUCKER_FIXTURE" "floating-v1"
  install_mock_curl

  run shiv run-url --floating "$FLOATING_URL"
  [ "$status" -eq 0 ]
  [[ "$output" == *"floating-v1"* ]]

  write_print_sucker "$SUCKER_FIXTURE" "floating-v2"
  run shiv run-url --floating "$FLOATING_URL"
  [ "$status" -eq 0 ]
  [[ "$output" == *"floating-v2"* ]]
  [ "$(wc -l < "$CURL_LOG" | tr -d ' ')" -eq 2 ]
}

@test "run-url: propagates sucker exit status and output" {
  set_sucker_fixture "$TEST_HOME/sucker.py"
  write_exit_sucker "$SUCKER_FIXTURE"
  install_mock_curl

  run shiv run-url "$PINNED_URL"
  [ "$status" -eq 7 ]
  [[ "$output" == *"before exit"* ]]
  [[ "$output" == *"exit stderr"* ]]
}

@test "run-url: rejects query strings before download" {
  set_sucker_fixture "$TEST_HOME/sucker.py"
  write_print_sucker "$SUCKER_FIXTURE" "unused"
  install_mock_curl

  run shiv run-url "${PINNED_URL}?token=secret"
  [ "$status" -eq 1 ]
  [[ "$output" == *"query strings and fragments are not supported"* ]]
  [ ! -s "$CURL_LOG" ]
}

@test "run-url: rejects unsupported script shebang" {
  set_sucker_fixture "$TEST_HOME/sucker.sh"
  cat > "$SUCKER_FIXTURE" <<'SH'
#!/usr/bin/env bash
echo shell
SH
  install_mock_curl

  run shiv run-url "$PINNED_URL"
  [ "$status" -eq 1 ]
  [[ "$output" == *"unsupported sucker script"* ]]
  [[ "$output" == *"uv run --script"* ]]
}
