# Caller environment snapshots

Generated shims snapshot exported variables in the package's sanitized uppercase
namespace before entering package Mise. For example, `my-tool` snapshots
`MY_TOOL_PROVIDER` as `SHIV_CALLER_MY_TOOL_PROVIDER`.

Every invocation clears stale snapshots for that package, then copies current
values exactly, including empty values and newlines. Unexported shell variables
are not inputs. Other packages' snapshots remain available for nested calls.
Reserved `SHIV_CALLER_*` handoff variables are never themselves snapshotted.
The shim refreshes `<PACKAGE>_CALLER_PWD` separately; it is not a caller setting.

Snapshots are transport, not restoration. Mise still owns package environment
and tool selection. This first implementation does not yet provide
`shiv env restore` or consume `[_.shiv].caller_env`. Consumers must not assume
that a snapshot alone overrides a package setting.

Do not log snapshots or dump environments: values may contain credentials.
Handoff variables are not a security boundary against code running as the same
OS user. Existing installed shims are unchanged until deliberately regenerated.
