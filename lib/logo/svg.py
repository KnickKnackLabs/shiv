"""Minimal SVG builder — no dependencies, just string construction."""

from __future__ import annotations

from typing import Optional
from xml.sax.saxutils import quoteattr


class SvgElement:
    """A single SVG element with attributes and optional children."""

    def __init__(self, tag: str, **attrs: str | int | float):
        self.tag = tag
        self.attrs = attrs
        self.children: list[SvgElement | str] = []

    def add(self, child: SvgElement | str) -> SvgElement:
        self.children.append(child)
        return child if isinstance(child, SvgElement) else self

    def render(self, indent: int = 0) -> str:
        pad = "  " * indent
        parts = [f"{pad}<{self.tag}"]
        for k, v in self.attrs.items():
            attr_name = k.replace("_", "-")
            parts.append(f" {attr_name}={quoteattr(str(v))}")

        if not self.children:
            parts.append(" />")
            return "".join(parts)

        parts.append(">")
        lines = ["".join(parts)]
        for child in self.children:
            if isinstance(child, str):
                lines.append(f"{pad}  {child}")
            else:
                lines.append(child.render(indent + 1))
        lines.append(f"{pad}</{self.tag}>")
        return "\n".join(lines)


class SvgDocument:
    """Root SVG document builder."""

    def __init__(self, width: int | float, height: int | float):
        self.root = SvgElement(
            "svg",
            xmlns="http://www.w3.org/2000/svg",
            width=width,
            height=height,
            viewBox=f"0 0 {width} {height}",
        )

    def add(self, element: SvgElement) -> SvgElement:
        return self.root.add(element)

    def defs(self) -> SvgElement:
        d = SvgElement("defs")
        self.root.add(d)
        return d

    def group(self, **attrs: str | int | float) -> SvgElement:
        g = SvgElement("g", **attrs)
        self.root.add(g)
        return g

    def rect(self, x: float, y: float, w: float, h: float, **attrs) -> SvgElement:
        el = SvgElement("rect", x=x, y=y, width=w, height=h, **attrs)
        self.root.add(el)
        return el

    def circle(self, cx: float, cy: float, r: float, **attrs) -> SvgElement:
        el = SvgElement("circle", cx=cx, cy=cy, r=r, **attrs)
        self.root.add(el)
        return el

    def render(self) -> str:
        header = '<?xml version="1.0" encoding="UTF-8"?>'
        return f"{header}\n{self.root.render()}"
