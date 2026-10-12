#!/usr/bin/env bash
# Install-time generation of a package's self-contained Mise restoration hook.

shiv_toml_string() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/\\n}"
  value="${value//$'\r'/\\r}"
  value="${value//$'\t'/\\t}"
  printf '"%s"' "$value"
}

# Each shim revision gets a new directory. Publish the shim only after both files
# exist; an older running shim keeps its original artifacts during regeneration.
shiv_create_restoration() {
  local package_dir="$1" directory="$2" owner="$3" config='' config_key=''
  local candidate config_directory
  for candidate in mise.toml .mise.toml .mise/config.toml .config/mise/config.toml; do
    if [ -f "$package_dir/$candidate" ]; then
      config="$package_dir/$candidate"
      config_directory=$(cd "$(dirname "$config")" && pwd -P) || return 1
      config_key=$(shiv_caller_env_key "$config_directory") || return 1
      break
    fi
  done

  # Dollar expressions below belong to generated Bash, not this generator.
  # shellcheck disable=SC2016
  if ! {
    printf '%s\n' '#!/usr/bin/env bash' '# managed by shiv; no caller values are stored here' &&
    shiv_embed_shim_source "$REPO_LIB_DIR/caller-env.sh" &&
    shiv_embed_shim_source "$REPO_LIB_DIR/env-restore.sh" &&
    printf '\n_shiv_restore_generated() {\n  local exports\n' &&
    if [ -n "$config" ]; then
      printf '  export %s\n' "$(shiv_shell_quote "SHIV_CALLER_OWNER_${config_key}=$owner")" &&
      printf '  exports=$(shiv_restore_caller_env %s true) || return 1\n' \
        "$(shiv_shell_quote "$config")" &&
      printf '  eval "$exports"\n'
    else
      printf '  return 0\n'
    fi &&
    printf '}\n_shiv_restore_generated\n'
  } > "$directory/restore.sh"; then
    return 1
  fi

  {
    printf '[env]\n_.source = { path = ' &&
    shiv_toml_string "$directory/restore.sh" &&
    printf ', tools = true }\n'
  } > "$directory/restore.toml"
}
