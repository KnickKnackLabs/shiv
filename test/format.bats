#!/usr/bin/env bats
# Tests for lib/format.sh utilities

REPO_DIR="$BATS_TEST_DIRNAME/.."

setup() {
  source "$REPO_DIR/lib/format.sh"
}

@test "strip_ansi removes color codes" {
  input=$'\e[31mERROR\e[0m something broke'
  result=$(echo "$input" | strip_ansi)
  [ "$result" = "ERROR something broke" ]
}

@test "strip_ansi removes bold and combined codes" {
  input=$'\e[1;33mWARNING\e[0m: check this'
  result=$(echo "$input" | strip_ansi)
  [ "$result" = "WARNING: check this" ]
}

@test "strip_ansi passes through plain text unchanged" {
  input="no escape codes here"
  result=$(echo "$input" | strip_ansi)
  [ "$result" = "$input" ]
}

@test "strip_ansi handles empty input" {
  result=$(echo "" | strip_ansi)
  [ "$result" = "" ]
}

@test "strip_ansi removes cursor movement codes" {
  input=$'\e[2Khello\e[1Aworld'
  result=$(echo "$input" | strip_ansi)
  [ "$result" = "helloworld" ]
}

@test "strip_ansi removes terminal mode sequences" {
  input=$'\e[?25l\e[?2004hvisible text\e[?25h\e[?2004l'
  result=$(echo "$input" | strip_ansi)
  [ "$result" = "visible text" ]
}
