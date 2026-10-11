#!/usr/bin/env bash
# Caller-setting snapshots are embedded in generated shims.

shiv_snapshot_caller_env() {
  local prefix="$1" names name snapshot
  local IFS=$'\n'

  # Enumerate names only. Reading values through indirect expansion preserves
  # newlines and shell punctuation without parsing or evaluating either.
  names=$(compgen -e) || return 1

  # A missing caller setting must not revive an inherited, stale snapshot.
  for name in $names; do
    case "$name" in
      "SHIV_CALLER_${prefix}"*) unset "$name" ;;
    esac
  done

  for name in $names; do
    case "$name" in
      SHIV_CALLER_*|"${prefix}CALLER_PWD") continue ;;
      "$prefix"*)
        snapshot="SHIV_CALLER_$name"
        export "$snapshot=${!name}"
        ;;
    esac
  done
}
