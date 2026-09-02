<div align="center">

![shiv](assets/logo.png)<br />

# shiv

**Package manager for git-based CLI tools.**

![shell: bash](https://img.shields.io/badge/shell-bash-4EAA25?style=flat&logo=gnubash&logoColor=white)
[![runtime: mise](https://img.shields.io/badge/runtime-mise-7c3aed?style=flat)](https://mise.jdx.dev)
![tests: 323 passing](https://img.shields.io/badge/tests-323%20passing-brightgreen?style=flat)
![packages: 49](https://img.shields.io/badge/packages-49-blue?style=flat)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue?style=flat)](LICENSE)

</div>

## What it does

A shiv package is a git repo with a `mise.toml` and tasks in `.mise/tasks/`. shiv clones the repo, resolves its dependencies, and puts a shim on your PATH. From then on it's a regular command — version-controlled, self-updating, with tab completions.

```bash
# Install a tool
shiv install shimmer

# Use it — spaces work as namespace separators
shimmer agent message k7r2 "hello"

# Check the installed version
shimmer --version

# See what's installed
shiv list

# Update package refs, then regenerate every clean registered shim
shiv update
shiv reshim

# Check health
shiv doctor
```

shiv manages itself the same way. It's a shiv package too.

## How it works

When you run `shiv install foo`, shiv:

1. Looks up `foo` in the package index ([`sources.json`](sources.json))
2. Clones the repo to `~/.local/share/shiv/packages/foo/`
3. Runs `mise install` to resolve dependencies
4. Generates a shim at `~/.local/bin/foo`
5. Registers the package in `~/.config/shiv/registry.json`

The shim is a bash script that forwards commands to `mise -C <repo> run`. It exports a package-specific caller variable (for example, `SHIMMER_CALLER_PWD`) so tools know where you invoked them, translates space-separated arguments to colon-joined task names (`agent message` → `agent:message`), reports the package's exact tag or commit through `--version`, and provides tab completions for all available tasks.

## Install

```bash
curl -fsSL shiv.knacklabs.co/install.sh | bash
```

Or on Windows:

```powershell
irm shiv.knacklabs.co/install.ps1 | iex
```

Both platforms are fully supported. The installer detects your environment, installs [mise](https://mise.jdx.dev) if needed, clones shiv, configures package sources, and sets up shell integration. On Windows, shiv generates `.ps1` and `.cmd` shims and configures your PowerShell profile.

<details>
<summary><b>What does the installer do?</b></summary>

1. Detects OS, architecture, and shell
2. Installs mise if not present (via winget on Windows)
3. Clones shiv and resolves its dependencies
4. Configures package source registries
5. Creates the self-hosting shiv shim and sets up shell integration
6. Verifies the installation

</details>

Add this to your shell config to activate shiv on startup:

```bash
eval "$(shiv shell)"
```

## Package sources

shiv looks up packages from JSON source files in `~/.config/shiv/sources/`. The installer seeds this directory with the default [KnickKnackLabs index](sources.json). Add your own by dropping a JSON file there:

```bash
# ~/.config/shiv/sources/my-org.json
{
  "my-tool": "my-org/my-tool",
  "another": "my-org/another"
}
```

By default, package-index installs use the newest stable semver release tag. Use an explicit ref when you want branch tracking or an exact pin:

```bash
shiv install notes         # newest released semver tag
shiv install notes@latest  # same as bare install
shiv install notes@main    # track a branch explicitly
shiv install notes@v0.8.4  # pin an exact tag
shiv install notes@abc1234 # pin an exact commit
```

`shiv update` preserves that intent: release-channel installs advance to the newest release tag, branch installs pull their branch, and exact tag/commit pins stay fixed until you reinstall at another ref. Legacy installs without recorded intent are refused with guidance to choose `@latest` or `@main` explicitly.

When the caller's mise context resolves a package name to a different Shiv checkout than the global registry, `shiv update` and `shiv list` refuse and show both roots instead of reporting registry state as if it described the executable package. Refresh the active `shiv:<name>` tool through mise, or run the command from a directory where that tool is not active.

`shiv reshim` regenerates shims and caches for every clean registered package without moving its Git ref. Dirty, missing, or invalid registered worktrees are reported and make the command fail after safe packages finish; unregistered package directories are never scanned. After upgrading Shiv itself, run `shiv update shiv` followed by `shiv reshim` so every active package uses the new generator.

You can also install directly from a local path:

```bash
shiv install my-tool /path/to/repo
```

## Suckers: tiny remote tasklets

Some useful tools are smaller than a package. `shiv run-url` runs a single pinned uv script from a raw URL without cloning a repo. Use it for small diagnostics, migrations, and experiments that may or may not grow into packages later.

```bash
# Pinned GitHub raw or gist URL required by default
shiv run-url https://raw.githubusercontent.com/owner/repo/<commit>/task.py --json

# Floating URLs are allowed only when made explicit
shiv run-url --floating https://raw.githubusercontent.com/owner/repo/main/task.py
```

Remote code execution is the point and the risk: pinned revisions are the default, query strings are rejected, downloads are cached by content hash, and the script receives `SUCKER_CALLER_PWD` for the directory where you invoked shiv.

## Writing a shiv package

Any git repo with a `mise.toml` and executable scripts in `.mise/tasks/` is a shiv package. Each task becomes a subcommand:

```bash
my-tool/
├── mise.toml          # dependencies
└── .mise/tasks/
    ├── hello          # → my-tool hello
    └── greet/
        └── world      # → my-tool greet world (or greet:world)
```

To make it installable by name, add it to a [source file](sources.json). To register it in the default index, add an entry to `sources.json` in this repo.

## Development

```bash
git clone https://github.com/KnickKnackLabs/shiv.git
cd shiv && mise trust && mise install
mise run test
```

Tests use the [KKL-maintained BATS fork](https://github.com/KnickKnackLabs/bats-core) with Rush. The measured eight-job default schedules isolated tests across and within files, covering 323 tests across 18 suites. Use `mise run test --jobs 1` for serial debugging. Completion tests run separately.

<div align="center">

## License

MIT

Built with [readme](https://github.com/KnickKnackLabs/readme). Named after the weapon, not the act.

</div>
