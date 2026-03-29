<div align="center">

![shiv](assets/logo.png)<br />

# shiv

**Package manager for git-based CLI tools.**

![shell: bash](https://img.shields.io/badge/shell-bash-4EAA25?style=flat&logo=gnubash&logoColor=white)
[![runtime: mise](https://img.shields.io/badge/runtime-mise-7c3aed?style=flat)](https://mise.jdx.dev)
![tests: 203 passing](https://img.shields.io/badge/tests-203%20passing-brightgreen?style=flat)
![packages: 27](https://img.shields.io/badge/packages-27-blue?style=flat)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue?style=flat)](LICENSE)

</div>

## What it does

A shiv package is a git repo with a `mise.toml` and tasks in `.mise/tasks/`. shiv clones the repo, resolves its dependencies, and puts a shim on your PATH. From then on it's a regular command — version-controlled, self-updating, with tab completions.

```bash
# Install a tool
shiv install shimmer

# Use it — spaces work as namespace separators
shimmer agent message k7r2 "hello"

# See what's installed
shiv list

# Update everything
shiv update

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

The shim is a bash script that forwards commands to `mise -C <repo> run`. It exports `CALLER_PWD` so tools know where you invoked them, translates space-separated arguments to colon-joined task names (`agent message` → `agent:message`), and provides tab completions for all available tasks.

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

You can also install directly from a local path:

```bash
shiv install my-tool /path/to/repo
```

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

Tests use [BATS](https://github.com/bats-core/bats-core) — 203 tests across 9 suites.

<div align="center">

## License

MIT

Built with [readme](https://github.com/KnickKnackLabs/readme). Named after the weapon, not the act.

</div>
