"""CLI entry point for logo generation."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from .config import LogoConfig
from .palettes import list_palettes, get_palette
from .renderers import get_renderer, list_renderers


def cmd_generate(args: argparse.Namespace) -> None:
    """Generate a logo from config or CLI flags."""
    if args.config:
        config = LogoConfig.from_file(args.config)
    else:
        config = LogoConfig()

    # CLI flags override config file values
    for field_name in (
        "renderer", "size", "columns", "rows", "gap",
        "corner_radius", "shape", "palette", "seed", "background",
    ):
        cli_val = getattr(args, field_name, None)
        if cli_val is not None:
            setattr(config, field_name, cli_val)

    if args.colors:
        config.colors = args.colors

    renderer_cls = get_renderer(config.renderer)
    renderer = renderer_cls(config)
    svg = renderer.render_string()

    output = args.output or "-"
    if output == "-":
        sys.stdout.write(svg)
    else:
        Path(output).write_text(svg)
        print(f"Written to {output}", file=sys.stderr)


def cmd_palettes(args: argparse.Namespace) -> None:
    """List available palettes, optionally with swatches."""
    if args.json:
        data = {name: get_palette(name) for name in list_palettes()}
        json.dump(data, sys.stdout, indent=2)
        print()
        return

    for name in list_palettes():
        colors = get_palette(name)
        swatches = " ".join(colors[:8])
        more = f" (+{len(colors) - 8} more)" if len(colors) > 8 else ""
        print(f"  {name:12s}  {swatches}{more}")


def cmd_renderers(args: argparse.Namespace) -> None:
    """List available renderers."""
    for name in list_renderers():
        print(f"  {name}")


def cmd_config(args: argparse.Namespace) -> None:
    """Dump a default config as JSON."""
    config = LogoConfig()
    json.dump(config.to_dict(), sys.stdout, indent=2)
    print()


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(
        prog="logo",
        description="Generate logos from pluggable renderers and color palettes.",
    )
    sub = parser.add_subparsers(dest="command")

    # --- generate ---
    gen = sub.add_parser("generate", help="Generate a logo")
    gen.add_argument("-c", "--config", help="Path to JSON config file")
    gen.add_argument("-o", "--output", help="Output file (default: stdout)")
    gen.add_argument("-r", "--renderer", help="Renderer name")
    gen.add_argument("-s", "--size", type=int, help="Canvas size in px")
    gen.add_argument("--columns", type=int, help="Grid columns")
    gen.add_argument("--rows", type=int, help="Grid rows")
    gen.add_argument("--gap", type=float, help="Gap between cells")
    gen.add_argument("--corner-radius", type=float, help="Corner radius for squares")
    gen.add_argument("--shape", choices=["square", "circle", "diamond"], help="Cell shape")
    gen.add_argument("--palette", help="Color palette name")
    gen.add_argument("--seed", type=int, help="Random seed for reproducibility")
    gen.add_argument("--background", help="Background color (hex)")
    gen.add_argument("--colors", nargs="+", help="Explicit list of hex colors")

    # --- palettes ---
    pal = sub.add_parser("palettes", help="List color palettes")
    pal.add_argument("--json", action="store_true", help="Output as JSON")

    # --- renderers ---
    sub.add_parser("renderers", help="List available renderers")

    # --- config ---
    sub.add_parser("config", help="Dump default config as JSON")

    args = parser.parse_args(argv)

    if not args.command:
        parser.print_help()
        sys.exit(1)

    commands = {
        "generate": cmd_generate,
        "palettes": cmd_palettes,
        "renderers": cmd_renderers,
        "config": cmd_config,
    }
    commands[args.command](args)


if __name__ == "__main__":
    main()
