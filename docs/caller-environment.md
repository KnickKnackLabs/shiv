# Caller settings

Packages declare the caller settings they accept in their main Mise config:

```toml
[_.shiv]
caller_env = ["MYAPP_PROVIDER", "MYAPP_CONFIG"]
```

No package-owned restoration script or helper-only Shiv runtime dependency is
needed. During shim generation, Shiv writes a self-contained Bash file and an
additional TOML config under its cache. Mise executes that Bash file while
constructing the package environment and retains its exports.

Declared caller settings replace package defaults. Avoid relying on
`mise.local.toml` to override the same restored setting: precedence depends on
Mise's environment-resolution phase and task form.

On Mise 2026.10.8 on macOS, the generated hook's `tools = true` setting allows
ordinary local values to win for inline TOML tasks, but restored caller values
win for executable task files and `mise exec`. Marking the local value itself
`tools = true` made it win in all three tested forms. This is an observed caveat,
not a cross-version precedence guarantee; the restoration implementation is
unchanged.

An empty caller value replaces a default with an empty value. An absent value
leaves the default unchanged. Undeclared settings are not restored. Package tool
selection and PATH remain Mise-owned; Shiv does not unset `__MISE_DIFF` or carry
across the entire caller environment.

## Snapshots and nested calls

Before entering package Mise, generated shims snapshot exported variables in the
package's sanitized uppercase setting namespace. Snapshot ownership uses the full
original package name, encoded byte-for-byte as lowercase hexadecimal. For example,
`my-tool` snapshots `MY_TOOL_PROVIDER` as
`SHIV_CALLER_VALUE_6d792d746f6f6c_MY_TOOL_PROVIDER`.

Every invocation clears only that exact owner's snapshots, then copies current
values exactly, including empty values and newlines. Unexported shell variables
are not inputs. Other packages' snapshots remain available for nested calls.
`my`, `my-tool` and `my_tool` have distinct owners even though their setting
prefixes overlap or sanitize identically. Reserved `SHIV_CALLER_*` variables are
never snapshotted. The shim refreshes `<PACKAGE>_CALLER_PWD` separately.

Each shim also binds its physical package directory to its owner through
`SHIV_CALLER_OWNER_<encoded-directory>`. Restoration selects that directory's
owner rather than guessing from a folder name or using the most recently invoked
tool. When multiple package names share one physical directory, its latest
invocation selects the active owner.

At every package handoff, the shim replaces inherited
`MISE_DEFAULT_CONFIG_FILENAME` with its own generated config and scrubs
`MISE_OVERRIDE_CONFIG_FILENAMES`. Nested calls therefore use their own declaration
and restoration file. Existing package source hooks still run; no package hook
needs to invoke Shiv.

## Generated files and trust

Each shim revision gets a unique private directory under
`$SHIV_CACHE_DIR/shim-env`. The files contain only source code and paths, never
caller values. They are read-only after generation. The shim and its artifacts
are independent of Shiv's source checkout at runtime.

Generation assembles the files before atomically replacing the executable shim.
On failure, it removes only its new files and preserves the old shim. Successful
regeneration retains older artifacts so an already-running shim can finish.
There is no automatic garbage collection in this implementation. Removing these
files requires regenerating any shim that still references them; missing or
unreadable artifacts fail the call rather than silently using package defaults.

The shim adds only its exact generated TOML file to `MISE_TRUSTED_CONFIG_PATHS`,
retaining any existing operator-provided paths. It does not persist a trust grant
or trust the package directory. Mise's normal package trust policy remains in
force; paranoid-mode tests verify that the generated grant does not trust an
unrelated local config. Cache paths containing a colon are refused because Mise
uses colons to separate trusted paths.

The declaration is read at invocation time from the package's main config
(`mise.toml`, with `.mise.toml`, `.mise/config.toml` and
`.config/mise/config.toml` as fallbacks). A missing `caller_env` declaration is a
no-op. Only Mise's specific missing-key diagnostic is accepted as absence;
other read failures, malformed declarations and reserved variable names fail
closed. A package with no main config at generation time gets a no-op hook;
regenerate its shim after adding a config.

## Public helper and evidence

`shiv env restore /absolute/path/to/mise.toml` remains available for explicit
integrations. It emits Bash-quoted exports, buffers them until the complete
declaration validates, and requires an owner bound by a generated shim. Unlike
the automatic hook, a missing declaration is an error for this explicit command.
Do not log its output: it may contain credentials.

Fictional tests against Mise 2026.10.8 on macOS cover generated-only restoration,
actual caller Mise handoff, empty and multiline values, inline-task local
precedence, existing source composition, nested name collisions, missing
artifacts, narrow trust and failed assembly. A separate real backend consumer
proof passed installation and restoration through an executable task file;
a standalone matrix reproduced the task-form precedence caveat above.
Linux parity and cold released-consumer bootstrap are not established by these
tests. Secrets adoption remains a separate decision.

Handoff variables and generated files are not a security boundary against code
running as the same OS user. Existing installed shims do not change until they
are deliberately regenerated.
