#!/usr/bin/env bash
# Caller-setting transport shared by generated shims and env:restore.

shiv_caller_env_key() {
  local LC_ALL=C
  local value="$1" index

  # Hex-encode every byte, not just punctuation. Fixed-width bytes plus the
  # underscore separator keep full names distinct, including prefix pairs.
  for ((index = 0; index < ${#value}; index++)); do
    printf '%02x' "'${value:index:1}"
  done
}

shiv_caller_env_owner_for_config() {
  local config="$1" package_dir directory_key binding owner
  package_dir=$(cd "$(dirname "$config")" && pwd -P) || return 1
  directory_key=$(shiv_caller_env_key "$package_dir") || return 1
  binding="SHIV_CALLER_OWNER_$directory_key"
  owner="${!binding-}"

  # The consuming directory, not the most recently invoked tool (often Shiv),
  # selects the owner. A hook cannot infer a package name from its folder name.
  if ! [[ "$owner" =~ ^([0-9a-f][0-9a-f])+$ ]]; then
    printf '%s\n' 'shiv: env restore requires a generated-shim owner for the consuming directory' >&2
    return 1
  fi

  printf '%s' "$owner"
}

shiv_snapshot_caller_env() {
  local owner="$1" prefix="$2" names name snapshot
  local snapshot_prefix="SHIV_CALLER_VALUE_${owner}_"
  local IFS=$'\n'

  # Enumerate names only. Reading values through indirect expansion preserves
  # newlines and shell punctuation without parsing or evaluating either.
  names=$(compgen -e) || return 1

  # Only this full package name owns these snapshots. The setting prefix may
  # overlap another package's prefix; it must never select snapshots to clear.
  for name in $names; do
    case "$name" in
      "$snapshot_prefix"*) unset "$name" ;;
    esac
  done

  for name in $names; do
    case "$name" in
      SHIV_CALLER_*|"${prefix}CALLER_PWD") continue ;;
      "$prefix"*)
        snapshot="$snapshot_prefix$name"
        export "$snapshot=${!name}"
        ;;
    esac
  done
}
