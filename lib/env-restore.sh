#!/usr/bin/env bash
# Emit Bash exports for a package's explicit caller-setting declaration.

shiv_restore_error() {
  printf '%s\n' 'shiv: caller_env must be an array of environment-variable names' >&2
  return 1
}

# Missing declarations are optional only for the generated hook. Recognize Mise's
# specific missing-key diagnostic, not arbitrary parse, access or execution errors.
shiv_read_caller_declaration() {
  local config="$1" optional="${2:-false}" result first_line
  if result=$(MISE_COLOR=false MISE_FRIENDLY_ERROR=true "${MISE_BIN:-mise}" \
    config get --file "$config" _.shiv.caller_env 2>&1); then
    printf '%s' "$result"
    return 0
  fi

  first_line="${result%%$'\n'*}"
  if [ "$optional" = true ] && \
    [[ "$first_line" = 'mise ERROR Key not found: _.shiv.caller_env in '* ]]; then
    printf '[]'
    return 0
  fi

  printf '%s\n' "$result" >&2
  return 1
}

shiv_restore_caller_env() {
  local config="$1" optional="${2:-false}" owner declaration remaining name snapshot exports=''
  local item_pattern='^[[:space:]]*"([A-Za-z_][A-Za-z0-9_]*)"[[:space:]]*(,|$)'
  local bracket_pattern='^[[:space:]]*\[(.*)\][[:space:]]*$'

  if [[ "$config" != /* ]]; then
    printf '%s\n' 'shiv: env restore requires an absolute config path' >&2
    return 1
  fi

  # Read only the stored declaration, never the resolved environment. Mise's
  # normalized array rendering is accepted only for plain variable identifiers.
  declaration=$(shiv_read_caller_declaration "$config" "$optional") || return 1
  if ! [[ "$declaration" =~ $bracket_pattern ]]; then
    shiv_restore_error
    return 1
  fi
  remaining="${BASH_REMATCH[1]}"
  if [ -z "$remaining" ] && [ "$optional" = true ]; then
    return 0
  fi
  owner=$(shiv_caller_env_owner_for_config "$config") || return 1

  while [[ "$remaining" != '' ]]; do
    if ! [[ "$remaining" =~ $item_pattern ]]; then
      shiv_restore_error
      return 1
    fi
    name="${BASH_REMATCH[1]}"
    remaining="${remaining:${#BASH_REMATCH[0]}}"

    case "$name" in
      SHIV_CALLER_*|*_CALLER_PWD)
        printf '%s\n' 'shiv: caller_env cannot restore reserved handoff or caller-directory variables' >&2
        return 1
        ;;
    esac

    snapshot="SHIV_CALLER_VALUE_${owner}_$name"
    if [[ "${!snapshot+x}" = x ]]; then
      # %q preserves empty, multiline and shell-looking values without evaluating
      # them. Buffer until the entire declaration has passed validation.
      printf -v exports '%sexport %s=%q\n' "$exports" "$name" "${!snapshot}"
    fi
  done

  printf '%s' "$exports"
}
