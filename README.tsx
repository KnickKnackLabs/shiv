/** @jsxImportSource jsx-md */

import { readFileSync, readdirSync, statSync } from "fs";
import { join, resolve } from "path";

import {
  Heading, Paragraph, CodeBlock,
  Bold, Code, Link, Image, LineBreak,
  Badge, Badges, Center, Section, Details,
  List, Item,
} from "readme/src/components";

// ── Dynamic data ─────────────────────────────────────────────

const REPO_DIR = resolve(import.meta.dirname);

// Read the package index from sources.json
const packages: Record<string, string> = JSON.parse(
  readFileSync(join(REPO_DIR, "sources.json"), "utf-8"),
);
const packageCount = Object.keys(packages).length;

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
      <Image src="assets/logo.png" alt="shiv" title="" />
      <LineBreak />

      <Heading level={1}>shiv</Heading>

      <Paragraph>
        <Bold>Package manager for git-based CLI tools.</Bold>
      </Paragraph>

      <Badges>
        <Badge label="shell" value="bash" color="4EAA25" logo="gnubash" logoColor="white" />
        <Badge label="runtime" value="mise" color="7c3aed" href="https://mise.jdx.dev" />
        <Badge label="tests" value={`${testCount} passing`} color="brightgreen" />
        <Badge label="packages" value={`${packageCount}`} color="blue" />
        <Badge label="License" value="MIT" color="blue" href="LICENSE" />
      </Badges>
    </Center>

    <Section title="What it does">
      <Paragraph>
        A shiv package is a git repo with a{" "}
        <Code>mise.toml</Code> and tasks in <Code>.mise/tasks/</Code>.
        shiv clones the repo, resolves its dependencies, and puts a shim on
        your PATH. From then on it's a regular command — version-controlled,
        self-updating, with tab completions.
      </Paragraph>

      <CodeBlock lang="bash">{`# Install a tool
shiv install shimmer

# Use it — spaces work as namespace separators
shimmer agent message k7r2 "hello"

# See what's installed
shiv list

# Update everything
shiv update

# Check health
shiv doctor`}</CodeBlock>

      <Paragraph>
        shiv manages itself the same way. It's a shiv package too.
      </Paragraph>
    </Section>

    <Section title="How it works">
      <Paragraph>
        When you run <Code>shiv install foo</Code>, shiv:
      </Paragraph>

      <List ordered>
        <Item>Looks up <Code>foo</Code> in the package index (<Link href="sources.json"><Code>sources.json</Code></Link>)</Item>
        <Item>Clones the repo to <Code>~/.local/share/shiv/packages/foo/</Code></Item>
        <Item>Runs <Code>mise install</Code> to resolve dependencies</Item>
        <Item>Generates a shim at <Code>~/.local/bin/foo</Code></Item>
        <Item>Registers the package in <Code>~/.config/shiv/registry.json</Code></Item>
      </List>

      <Paragraph>
        The shim is a bash script that forwards commands to{" "}
        <Code>{"mise -C <repo> run"}</Code>. It exports{" "}
        <Code>CALLER_PWD</Code> so tools know where you invoked them,
        translates space-separated arguments to colon-joined task names
        (<Code>agent message</Code> → <Code>agent:message</Code>),
        and provides tab completions for all available tasks.
      </Paragraph>
    </Section>

    <Section title="Install">
      <CodeBlock lang="bash">{`curl -fsSL shiv.knacklabs.co/install.sh | bash`}</CodeBlock>

      <Paragraph>
        Or on Windows:
      </Paragraph>

      <CodeBlock lang="powershell">{`irm shiv.knacklabs.co/install.ps1 | iex`}</CodeBlock>

      <Paragraph>
        Both platforms are fully supported. The installer detects your
        environment, installs{" "}
        <Link href="https://mise.jdx.dev">mise</Link> if needed, clones shiv,
        configures package sources, and sets up shell integration.
        On Windows, shiv generates <Code>.ps1</Code> and <Code>.cmd</Code> shims
        and configures your PowerShell profile.
      </Paragraph>

      <Details summary="What does the installer do?">
        <List ordered>
          <Item>Detects OS, architecture, and shell</Item>
          <Item>Installs mise if not present (via winget on Windows)</Item>
          <Item>Clones shiv and resolves its dependencies</Item>
          <Item>Configures package source registries</Item>
          <Item>Creates the self-hosting shiv shim and sets up shell integration</Item>
          <Item>Verifies the installation</Item>
        </List>
      </Details>

      <Paragraph>
        Add this to your shell config to activate shiv on startup:
      </Paragraph>

      <CodeBlock lang="bash">{`eval "$(shiv shell)"`}</CodeBlock>
    </Section>

    <Section title="Package sources">
      <Paragraph>
        shiv looks up packages from JSON source files in{" "}
        <Code>~/.config/shiv/sources/</Code>. The installer seeds this
        directory with the default{" "}
        <Link href="sources.json">KnickKnackLabs index</Link>.
        Add your own by dropping a JSON file there:
      </Paragraph>

      <CodeBlock lang="bash">{`# ~/.config/shiv/sources/my-org.json
{
  "my-tool": "my-org/my-tool",
  "another": "my-org/another"
}`}</CodeBlock>

      <Paragraph>
        You can also install directly from a local path:
      </Paragraph>

      <CodeBlock lang="bash">{`shiv install my-tool /path/to/repo`}</CodeBlock>
    </Section>

    <Section title="Writing a shiv package">
      <Paragraph>
        Any git repo with a <Code>mise.toml</Code> and executable scripts
        in <Code>.mise/tasks/</Code> is a shiv package. Each task becomes
        a subcommand:
      </Paragraph>

      <CodeBlock lang="bash">{`my-tool/
├── mise.toml          # dependencies
└── .mise/tasks/
    ├── hello          # → my-tool hello
    └── greet/
        └── world      # → my-tool greet world (or greet:world)`}</CodeBlock>

      <Paragraph>
        To make it installable by name, add it to a{" "}
        <Link href="sources.json">source file</Link>. To register it in
        the default index, add an entry to{" "}
        <Code>sources.json</Code> in this repo.
      </Paragraph>
    </Section>

    <Section title="Development">
      <CodeBlock lang="bash">{`git clone https://github.com/KnickKnackLabs/shiv.git
cd shiv && mise trust && mise install
mise run test`}</CodeBlock>

      <Paragraph>
        Tests use <Link href="https://github.com/bats-core/bats-core">BATS</Link> — {testCount} tests
        across {testFiles.length} suites.
      </Paragraph>
    </Section>

    <Center>
      <Section title="License">
        <Paragraph>MIT</Paragraph>
      </Section>

      <Paragraph>
        {"Built with "}
        <Link href="https://github.com/KnickKnackLabs/readme">readme</Link>.
        {" Named after the weapon, not the act."}
      </Paragraph>
    </Center>
  </>
);

console.log(readme);
