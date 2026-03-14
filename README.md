<div align="center">

# shiv

**CLI shim manager for mise-based tools.**

One eval line. Every tool on your PATH.
No per-tool shell setup. No global installs. Just shims.

![shell: bash](https://img.shields.io/badge/shell-bash-4EAA25?style=flat&logo=gnubash&logoColor=white)
[![runtime: mise](https://img.shields.io/badge/runtime-mise-7c3aed?style=flat)](https://mise.jdx.dev)
![tests: 131 passing](https://img.shields.io/badge/tests-131%20passing-brightgreen?style=flat)
![packages: 12](https://img.shields.io/badge/packages-12-blue?style=flat)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue?style=flat)](LICENSE)

</div>

## What it does

shiv creates lightweight shell shims for tools managed by [mise](https://mise.jdx.dev). Each shim is a tiny bash script that forwards commands to the right repo via `mise run`. Install a tool once, and its tasks appear as commands on your PATH.

shiv manages itself the same way — it's a shiv package too.

## Install

```bash
curl -fsSL shiv.knacklabs.co/install.sh | bash
```

Or on Windows (PowerShell):

```powershell
irm shiv.knacklabs.co/install.ps1 | iex
```

The installer clones shiv, installs its dependencies, creates the self-hosting shim, and adds `~/.local/bin` to your PATH.

## Quick start

```bash
# Install a tool from the package index
shiv install shimmer

# See what's installed
shiv list

# Update everything
shiv update

# Check health
shiv doctor
```

## Commands

Generated from `.mise/tasks/` — 7 commands available:

| Command | Description |
| --- | --- |
| `shiv doctor` | Check health of all managed tools |
| `shiv install` | Install a tool — from the package index or a local path |
| `shiv list` | Show all managed tools |
| `shiv shell` | Output shell configuration (PATH, env vars) for eval |
| `shiv uninstall` | Remove a tool's shim and deregister it |
| `shiv update` | Pull latest and refresh shims — optionally for a single package |
| `shiv which` | Print the install path of a managed tool |

## How it works

When you run `shiv install foo`, shiv:

1. Looks up `foo` in the package index (`sources.json`)
2. Clones the repo to `~/.local/share/shiv/packages/foo/`
3. Runs `mise install` to set up the tool's dependencies
4. Creates a shim at `~/.local/bin/foo` that forwards to `mise run`
5. Registers the package in `~/.config/shiv/registry.json`

After that, running `foo <task>` anywhere invokes `mise -C <repo> run <task>` — no shell setup needed.

## Package index

12 packages available in the default index:

| Package | Repository |
| --- | --- |
| `audit` | [KnickKnackLabs/audit](https://github.com/KnickKnackLabs/audit) |
| `butthair` | [KnickKnackLabs/butthair](https://github.com/KnickKnackLabs/butthair) |
| `frames` | [KnickKnackLabs/frames](https://github.com/KnickKnackLabs/frames) |
| `ghpm` | [KnickKnackLabs/ghpm](https://github.com/KnickKnackLabs/ghpm) |
| `monkeys` | [KnickKnackLabs/monkeys](https://github.com/KnickKnackLabs/monkeys) |
| `readme` | [KnickKnackLabs/readme](https://github.com/KnickKnackLabs/readme) |
| `recorder` | [KnickKnackLabs/recorder](https://github.com/KnickKnackLabs/recorder) |
| `sessions` | [KnickKnackLabs/sessions](https://github.com/KnickKnackLabs/sessions) |
| `shimmer` | [KnickKnackLabs/shimmer](https://github.com/KnickKnackLabs/shimmer) |
| `wallpapers` | [KnickKnackLabs/wallpapers](https://github.com/KnickKnackLabs/wallpapers) |
| `websites` | [KnickKnackLabs/websites](https://github.com/KnickKnackLabs/websites) |
| `zettelkasten` | [KnickKnackLabs/zettelkasten](https://github.com/KnickKnackLabs/zettelkasten) |

Install from the index by name, or from a local path:

```bash
shiv install shimmer              # from the index
shiv install my-tool /path/to/repo  # from a local path
```

## Shell setup

Add this to your `.bashrc` or `.zshrc`:

```bash
eval "$(shiv shell)"
```

This adds `~/.local/bin` to your PATH and sets up tab completions for all installed packages.

## Development

```bash
git clone https://github.com/KnickKnackLabs/shiv.git
cd shiv && mise trust && mise install
mise run test
```

Tests use [BATS](https://github.com/bats-core/bats-core) — 131 tests across 7 suites covering doctor, list, update, completions, install, registry, uninstall.

<div align="center">

## License

MIT

This README was created using [readme](https://github.com/KnickKnackLabs/readme).

</div>
