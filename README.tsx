/** @jsxImportSource jsx-md */

import { readFileSync, readdirSync, statSync } from "fs";
import { join, resolve } from "path";

import {
  Heading, Paragraph, CodeBlock,
  Bold, Code, Link,
  Badge, Badges, Center, Section,
  Table, TableHead, TableRow, Cell,
  List, Item,
} from "readme/src/components";

// ── Dynamic data ─────────────────────────────────────────────

const REPO_DIR = resolve(import.meta.dirname);

// Extract commands from .mise/tasks/ — reads #MISE description= from each task file
const commands: { name: string; desc: string }[] = readdirSync(join(REPO_DIR, ".mise/tasks"))
  .filter((f) => {
    const full = join(REPO_DIR, ".mise/tasks", f);
    return statSync(full).isFile();
  })
  .map((f) => {
    const content = readFileSync(join(REPO_DIR, ".mise/tasks", f), "utf-8");
    const match = content.match(/#MISE description="(.+?)"/);
    return { name: f, desc: match?.[1] ?? "" };
  })
  .filter((c) => c.desc.length > 0)
  .sort((a, b) => a.name.localeCompare(b.name));

// Read the package index from sources.json
const packages: Record<string, string> = JSON.parse(
  readFileSync(join(REPO_DIR, "sources.json"), "utf-8"),
);
const packageNames = Object.keys(packages).sort();

// Count test files and test cases
const testDir = join(REPO_DIR, "test");
const testFiles = readdirSync(testDir).filter((f) => f.endsWith(".bats"));
const testCount = testFiles.reduce((sum, f) => {
  const content = readFileSync(join(testDir, f), "utf-8");
  return sum + (content.match(/@test /g)?.length ?? 0);
}, 0);

// ── README ───────────────────────────────────────────────────

const readme = (
  <>
    <Center>
      <Heading level={1}>shiv</Heading>

      <Paragraph>
        <Bold>CLI shim manager for mise-based tools.</Bold>
      </Paragraph>

      <Paragraph>
        One eval line. Every tool on your PATH.{"\n"}
        No per-tool shell setup. No global installs. Just shims.
      </Paragraph>

      <Badges>
        <Badge label="shell" value="bash" color="4EAA25" logo="gnubash" logoColor="white" />
        <Badge label="runtime" value="mise" color="7c3aed" href="https://mise.jdx.dev" />
        <Badge label="tests" value={`${testCount} passing`} color="brightgreen" />
        <Badge label="packages" value={`${packageNames.length}`} color="blue" />
        <Badge label="License" value="MIT" color="blue" href="LICENSE" />
      </Badges>
    </Center>

    <Section title="What it does">
      <Paragraph>
        shiv creates lightweight shell shims for tools managed by{" "}
        <Link href="https://mise.jdx.dev">mise</Link>. Each shim is a tiny bash
        script that forwards commands to the right repo via <Code>mise run</Code>.
        Install a tool once, and its tasks appear as commands on your PATH.
      </Paragraph>

      <Paragraph>
        shiv manages itself the same way — it's a shiv package too.
      </Paragraph>
    </Section>

    <Section title="Install">
      <CodeBlock lang="bash">{`curl -fsSL shiv.knacklabs.co/install.sh | bash`}</CodeBlock>

      <Paragraph>
        Or on Windows (PowerShell):
      </Paragraph>

      <CodeBlock lang="powershell">{`irm shiv.knacklabs.co/install.ps1 | iex`}</CodeBlock>

      <Paragraph>
        The installer clones shiv, installs its dependencies, creates the
        self-hosting shim, and adds <Code>~/.local/bin</Code> to your PATH.
      </Paragraph>
    </Section>

    <Section title="Quick start">
      <CodeBlock lang="bash">{`# Install a tool from the package index
shiv install shimmer

# See what's installed
shiv list

# Update everything
shiv update

# Check health
shiv doctor`}</CodeBlock>
    </Section>

    <Section title="Commands">
      <Paragraph>
        Generated from <Code>.mise/tasks/</Code> — {commands.length} commands available:
      </Paragraph>

      <Table>
        <TableHead>
          <Cell>Command</Cell>
          <Cell>Description</Cell>
        </TableHead>
        {commands.map((cmd) => (
          <TableRow>
            <Cell><Code>{`shiv ${cmd.name}`}</Code></Cell>
            <Cell>{cmd.desc}</Cell>
          </TableRow>
        ))}
      </Table>
    </Section>

    <Section title="How it works">
      <Paragraph>
        When you run <Code>shiv install foo</Code>, shiv:
      </Paragraph>

      <List ordered>
        <Item>Looks up <Code>foo</Code> in the package index (<Code>sources.json</Code>)</Item>
        <Item>Clones the repo to <Code>~/.local/share/shiv/packages/foo/</Code></Item>
        <Item>Runs <Code>mise install</Code> to set up the tool's dependencies</Item>
        <Item>Creates a shim at <Code>~/.local/bin/foo</Code> that forwards to <Code>mise run</Code></Item>
        <Item>Registers the package in <Code>~/.config/shiv/registry.json</Code></Item>
      </List>

      <Paragraph>
        After that, running <Code>{"foo <task>"}</Code> anywhere invokes{" "}
        <Code>{"mise -C <repo> run <task>"}</Code> — no shell setup needed.
      </Paragraph>
    </Section>

    <Section title="Package index">
      <Paragraph>
        {packageNames.length} packages available in the default index:
      </Paragraph>

      <Table>
        <TableHead>
          <Cell>Package</Cell>
          <Cell>Repository</Cell>
        </TableHead>
        {packageNames.map((name) => (
          <TableRow>
            <Cell><Code>{name}</Code></Cell>
            <Cell><Link href={`https://github.com/${packages[name]}`}>{packages[name]}</Link></Cell>
          </TableRow>
        ))}
      </Table>

      <Paragraph>
        Install from the index by name, or from a local path:
      </Paragraph>

      <CodeBlock lang="bash">{`shiv install shimmer              # from the index
shiv install my-tool /path/to/repo  # from a local path`}</CodeBlock>
    </Section>

    <Section title="Shell setup">
      <Paragraph>
        Add this to your <Code>.bashrc</Code> or <Code>.zshrc</Code>:
      </Paragraph>

      <CodeBlock lang="bash">{`eval "$(shiv shell)"`}</CodeBlock>

      <Paragraph>
        This adds <Code>~/.local/bin</Code> to your PATH and sets up tab completions
        for all installed packages.
      </Paragraph>
    </Section>

    <Section title="Development">
      <CodeBlock lang="bash">{`git clone https://github.com/KnickKnackLabs/shiv.git
cd shiv && mise trust && mise install
mise run test`}</CodeBlock>

      <Paragraph>
        Tests use <Link href="https://github.com/bats-core/bats-core">BATS</Link> — {testCount} tests
        across {testFiles.length} suites covering {testFiles.map((f) => f.replace(".bats", "")).join(", ")}.
      </Paragraph>
    </Section>

    <Center>
      <Section title="License">
        <Paragraph>MIT</Paragraph>
      </Section>
    </Center>
  </>
);

console.log(readme);
