# Caller environment snapshots

Generated shims snapshot exported variables in the package's sanitized uppercase
setting namespace before entering package Mise. Snapshot ownership uses the full
original package name, encoded byte-for-byte as lowercase hexadecimal. For example,
`my-tool` snapshots `MY_TOOL_PROVIDER` as
`SHIV_CALLER_VALUE_6d792d746f6f6c_MY_TOOL_PROVIDER`.

Every invocation clears only that exact owner's snapshots, then copies current
values exactly, including empty values and newlines. Unexported shell variables
are not inputs. Other packages' snapshots remain available for nested calls.
`my`, `my-tool` and `my_tool` have distinct owners even though their setting
prefixes overlap or sanitize identically. The setting names themselves do not change.
Reserved `SHIV_CALLER_*` handoff variables are never themselves snapshotted.
The shim refreshes `<PACKAGE>_CALLER_PWD` separately; it is not a caller setting.

Snapshots are transport, not restoration. Mise still owns package environment
and tool selection. Consumers declare which settings to restore:

```toml
[_.shiv]
caller_env = ["MYAPP_PROVIDER", "MYAPP_CONFIG"]

[env]
_.source = { path = "scripts/caller-env.sh", tools = true }
```

The consuming package's `scripts/caller-env.sh` uses the Shiv helper:

```bash
#!/usr/bin/env bash
package_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd) || exit 1
exports=$(shiv env restore "$package_dir/mise.toml") || exit 1
eval "$exports"
```

Declare Shiv as a runtime dependency so that `shiv` is available to this hook.
The helper reads the exact stored declaration through `mise config get`; the
config path must be absolute. Each generated shim also binds its physical package
directory to its encoded owner through `SHIV_CALLER_OWNER_<encoded-directory>`.
The helper resolves the consuming config's directory to select that owner, rather
than using the most recently called tool's name or guessing from a folder name.
For multiple names installed from one directory, the most recent invocation of
that directory selects its active owner. Missing or malformed owner bindings fail
closed; legacy unowned snapshots are not used.

It emits Bash-quoted exports only for declared settings with that owner's
snapshots. Empty values are restored; absent snapshots leave the
package environment unchanged. Invalid declarations and reserved handoff or
caller-directory names fail before any export is emitted.

The hook and public helper were tested with fictional values against Mise
2026.9.12. Generated-shim tests cover shorter prefixes and sanitized-name
collisions; nested Mise task tests restore each consuming directory's owner through
the public helper. Cold dependency bootstrap and broader nested consumer behavior
still need proof before adoption in Secrets.

Do not log snapshots or dump environments: values may contain credentials.
Handoff variables are not a security boundary against code running as the same
OS user. Existing installed shims are unchanged until deliberately regenerated.
