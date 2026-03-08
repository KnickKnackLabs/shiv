#!/usr/bin/env bats
# shiv shell completions test suite

REPO_DIR="$BATS_TEST_DIRNAME/.."

setup() {
  source "$REPO_DIR/lib/shim.sh"

  # Use a temporary home for isolation
  export TEST_HOME="$BATS_TMPDIR/shiv-test-$$"
  mkdir -p "$TEST_HOME"

  # Override shiv paths to use test home
  export SHIV_BIN_DIR="$TEST_HOME/.local/bin"
  export SHIV_DATA_DIR="$TEST_HOME/.local/share/shiv"
  export SHIV_PACKAGES_DIR="$SHIV_DATA_DIR/packages"
  export SHIV_CONFIG_DIR="$TEST_HOME/.config/shiv"
  export SHIV_CACHE_DIR="$TEST_HOME/.cache/shiv"
  export SHIV_REGISTRY="$SHIV_CONFIG_DIR/registry.json"
  export SHIV_SOURCES_DIR="$SHIV_CONFIG_DIR/sources"

  # Register shiv itself as a test package
  shiv_init_registry
  shiv_register "shiv" "$REPO_DIR"
}

teardown() {
  rm -rf "$TEST_HOME"
}

# ============================================================================
# Cache generation
# ============================================================================

@test "cache: shiv_cache_tasks creates cache file" {
  shiv_cache_tasks "shiv" "$REPO_DIR"
  [ -f "$SHIV_CACHE_DIR/completions/shiv.cache" ]
}

@test "cache: cache contains known tasks" {
  shiv_cache_tasks "shiv" "$REPO_DIR"
  grep -q "^install" "$SHIV_CACHE_DIR/completions/shiv.cache"
  grep -q "^list" "$SHIV_CACHE_DIR/completions/shiv.cache"
  grep -q "^doctor" "$SHIV_CACHE_DIR/completions/shiv.cache"
}

@test "cache: cache format is tab-separated name and description" {
  shiv_cache_tasks "shiv" "$REPO_DIR"
  # Every non-empty line should have exactly one tab
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    tab_count=$(echo "$line" | tr -cd '\t' | wc -c | tr -d ' ')
    [ "$tab_count" -eq 1 ]
  done < "$SHIV_CACHE_DIR/completions/shiv.cache"
}

@test "cache: shiv_cache_remove deletes cache file" {
  shiv_cache_tasks "shiv" "$REPO_DIR"
  [ -f "$SHIV_CACHE_DIR/completions/shiv.cache" ]
  shiv_cache_remove "shiv"
  [ ! -f "$SHIV_CACHE_DIR/completions/shiv.cache" ]
}

@test "cache: shiv_cache_remove is safe on missing file" {
  run shiv_cache_remove "nonexistent"
  [ "$status" -eq 0 ]
}

# ============================================================================
# Bash completions
# ============================================================================

@test "bash: output contains complete -F for registered tool" {
  shiv_cache_tasks "shiv" "$REPO_DIR"
  run mise -C "$REPO_DIR" run -q completions:bash
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "complete -F _shiv_complete_shiv shiv"
}

@test "bash: output contains __shiv_rebuild_cache helper" {
  shiv_cache_tasks "shiv" "$REPO_DIR"
  run mise -C "$REPO_DIR" run -q completions:bash
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "__shiv_rebuild_cache()"
}

@test "bash: completions function works" {
  shiv_cache_tasks "shiv" "$REPO_DIR"
  eval "$(mise -C "$REPO_DIR" run -q completions:bash)"
  COMP_WORDS=(shiv "")
  COMP_CWORD=1
  _shiv_complete_shiv
  [[ " ${COMPREPLY[*]} " == *" install "* ]]
  [[ " ${COMPREPLY[*]} " == *" list "* ]]
  [[ " ${COMPREPLY[*]} " == *" doctor "* ]]
}

@test "bash: completions filter by prefix" {
  shiv_cache_tasks "shiv" "$REPO_DIR"
  eval "$(mise -C "$REPO_DIR" run -q completions:bash)"
  COMP_WORDS=(shiv "in")
  COMP_CWORD=1
  _shiv_complete_shiv
  [[ " ${COMPREPLY[*]} " == *" install "* ]]
  [[ " ${COMPREPLY[*]} " != *" doctor "* ]]
}

@test "bash: lazy cache rebuild on missing cache" {
  # Pre-populate then truncate — so the generated script has the right path baked in
  # Use truncate (empty file) rather than delete, to test the -s (non-empty) check
  shiv_cache_tasks "shiv" "$REPO_DIR"
  : > "$SHIV_CACHE_DIR/completions/shiv.cache"
  eval "$(mise -C "$REPO_DIR" run -q completions:bash)"
  COMP_WORDS=(shiv "")
  COMP_CWORD=1
  _shiv_complete_shiv
  # Should have rebuilt cache and produced completions
  [[ " ${COMPREPLY[*]} " == *" install "* ]]
  [ -f "$SHIV_CACHE_DIR/completions/shiv.cache" ]
}

# ============================================================================
# Zsh completions
# ============================================================================

@test "zsh: output contains compdef for registered tool" {
  shiv_cache_tasks "shiv" "$REPO_DIR"
  run mise -C "$REPO_DIR" run -q completions:zsh
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "compdef _shiv_complete_shiv shiv"
}

@test "zsh: output contains _describe call" {
  shiv_cache_tasks "shiv" "$REPO_DIR"
  run mise -C "$REPO_DIR" run -q completions:zsh
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "_describe"
}

@test "zsh: output escapes colons in task names" {
  shiv_cache_tasks "shiv" "$REPO_DIR"
  run mise -C "$REPO_DIR" run -q completions:zsh
  [ "$status" -eq 0 ]
  # The escaping logic should be present
  echo "$output" | grep -qF 'task//:/\\:'
}

@test "zsh: valid syntax" {
  if ! command -v zsh &>/dev/null; then
    skip "zsh not found"
  fi
  shiv_cache_tasks "shiv" "$REPO_DIR"
  mise -C "$REPO_DIR" run -q completions:zsh > "$BATS_TMPDIR/comp.zsh"
  run zsh -n "$BATS_TMPDIR/comp.zsh"
  [ "$status" -eq 0 ]
}

# ============================================================================
# Fish completions
# ============================================================================

@test "fish: output contains complete -c for registered tool" {
  shiv_cache_tasks "shiv" "$REPO_DIR"
  run mise -C "$REPO_DIR" run -q completions:fish
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "complete -c shiv"
}

@test "fish: output contains __shiv_rebuild_cache helper" {
  shiv_cache_tasks "shiv" "$REPO_DIR"
  run mise -C "$REPO_DIR" run -q completions:fish
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "__shiv_rebuild_cache"
}

@test "fish: valid syntax" {
  if ! command -v fish &>/dev/null; then
    skip "fish not found"
  fi
  shiv_cache_tasks "shiv" "$REPO_DIR"
  mise -C "$REPO_DIR" run -q completions:fish > "$BATS_TMPDIR/comp.fish"
  run fish -n "$BATS_TMPDIR/comp.fish"
  [ "$status" -eq 0 ]
}

# ============================================================================
# Auto-detect (default)
# ============================================================================

@test "default: auto-detects bash" {
  shiv_cache_tasks "shiv" "$REPO_DIR"
  SHELL=/bin/bash run mise -C "$REPO_DIR" run -q completions
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "complete -F"
}

@test "default: auto-detects zsh" {
  shiv_cache_tasks "shiv" "$REPO_DIR"
  SHELL=/bin/zsh run mise -C "$REPO_DIR" run -q completions
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "compdef"
}

@test "default: rejects unsupported shell" {
  SHELL=/bin/csh run mise -C "$REPO_DIR" run -q completions
  [ "$status" -ne 0 ]
}

# ============================================================================
# Multiple tools
# ============================================================================

@test "multiple: completions cover all registered tools" {
  # Register a second tool (use shiv repo again under a different name)
  shiv_register "faketool" "$REPO_DIR"
  shiv_cache_tasks "shiv" "$REPO_DIR"
  shiv_cache_tasks "faketool" "$REPO_DIR"

  run mise -C "$REPO_DIR" run -q completions:bash
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "complete -F _shiv_complete_shiv shiv"
  echo "$output" | grep -q "complete -F _shiv_complete_faketool faketool"
}
