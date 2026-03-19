"""Color palette definitions and utilities."""

from __future__ import annotations

import colorsys
import random
from typing import Optional

# Built-in palettes — each is a list of hex colors
PALETTES: dict[str, list[str]] = {
    "vivid": [
        "#FF6B6B", "#FF8E53", "#FFCD56", "#4BC0C0", "#36A2EB",
        "#9966FF", "#FF6384", "#C9CBCF", "#4ECDC4", "#45B7D1",
        "#96CEB4", "#FFEAA7", "#DDA0DD", "#98D8C8", "#F7DC6F",
        "#BB8FCE", "#85C1E9", "#F8C471", "#82E0AA", "#F1948A",
        "#D7BDE2", "#A3E4D7", "#FAD7A0", "#AED6F1", "#F5B7B1",
    ],
    "pastel": [
        "#FFB3BA", "#FFDFBA", "#FFFFBA", "#BAFFC9", "#BAE1FF",
        "#E8BAFF", "#FFB3DE", "#B3FFE8", "#FFE8B3", "#B3D4FF",
        "#D4B3FF", "#B3FFB3", "#FFB3B3", "#B3FFFF", "#FFE0B3",
        "#E0B3FF", "#B3FFD4", "#FFB3E8", "#D4FFB3", "#B3E8FF",
        "#FFD4B3", "#B3FFE0", "#FFB3D4", "#E8FFB3", "#B3B3FF",
    ],
    "neon": [
        "#FF0080", "#FF00FF", "#8000FF", "#0000FF", "#0080FF",
        "#00FFFF", "#00FF80", "#00FF00", "#80FF00", "#FFFF00",
        "#FF8000", "#FF0000", "#FF0040", "#FF00BF", "#4000FF",
        "#0040FF", "#00FFBF", "#00FF40", "#40FF00", "#BFFF00",
        "#FFbF00", "#FF4000", "#FF0060", "#FF00DF", "#6000FF",
    ],
    "earth": [
        "#8B4513", "#A0522D", "#CD853F", "#DEB887", "#D2B48C",
        "#BC8F8F", "#F4A460", "#DAA520", "#B8860B", "#808000",
        "#556B2F", "#6B8E23", "#8FBC8F", "#2E8B57", "#228B22",
        "#006400", "#4682B4", "#5F9EA0", "#708090", "#778899",
        "#696969", "#A9A9A9", "#BDB76B", "#D2691E", "#CD5C5C",
    ],
    "ocean": [
        "#001F3F", "#003366", "#004080", "#005599", "#006BB3",
        "#0080CC", "#0099E6", "#00B3FF", "#33C1FF", "#66CFFF",
        "#99DDFF", "#CCEBFF", "#004D40", "#00695C", "#00796B",
        "#00897B", "#009688", "#26A69A", "#4DB6AC", "#80CBC4",
        "#B2DFDB", "#E0F2F1", "#0D47A1", "#1565C0", "#1976D2",
    ],
    "sunset": [
        "#FF6B35", "#FF8C42", "#FFAD60", "#FFD166", "#F4845F",
        "#F27059", "#F25C54", "#D62828", "#E85D04", "#FAA307",
        "#FCBF49", "#EAE2B7", "#F77F00", "#FC5C65", "#FD9644",
        "#FED330", "#FC5C65", "#EB3B5A", "#FA8231", "#F7B731",
        "#20BF6B", "#0FB9B1", "#2D98DA", "#4B7BEC", "#A55EEA",
    ],
    "monochrome": [
        "#000000", "#1A1A1A", "#333333", "#4D4D4D", "#666666",
        "#808080", "#999999", "#B3B3B3", "#CCCCCC", "#E6E6E6",
        "#F2F2F2", "#0D0D0D", "#262626", "#404040", "#595959",
        "#737373", "#8C8C8C", "#A6A6A6", "#BFBFBF", "#D9D9D9",
        "#F0F0F0", "#E8E8E8", "#D0D0D0", "#B8B8B8", "#A0A0A0",
    ],
}


def get_palette(name: str) -> list[str]:
    """Get a named palette. Raises KeyError if not found."""
    if name not in PALETTES:
        available = ", ".join(sorted(PALETTES.keys()))
        raise KeyError(f"Unknown palette '{name}'. Available: {available}")
    return list(PALETTES[name])


def list_palettes() -> list[str]:
    """Return sorted list of available palette names."""
    return sorted(PALETTES.keys())


def pick_colors(
    count: int,
    palette: str = "vivid",
    seed: Optional[int] = None,
) -> list[str]:
    """Pick `count` colors from a palette, shuffled for variety."""
    rng = random.Random(seed)
    colors = get_palette(palette)
    if count <= len(colors):
        picked = rng.sample(colors, count)
    else:
        # Repeat and shuffle to fill
        picked = []
        while len(picked) < count:
            batch = list(colors)
            rng.shuffle(batch)
            picked.extend(batch)
        picked = picked[:count]
    return picked


def hex_to_rgb(hex_color: str) -> tuple[int, int, int]:
    """Convert hex color to RGB tuple."""
    h = hex_color.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16))


def rgb_to_hex(r: int, g: int, b: int) -> str:
    """Convert RGB tuple to hex color."""
    return f"#{r:02X}{g:02X}{b:02X}"


def generate_gradient(start: str, end: str, steps: int) -> list[str]:
    """Generate a gradient between two hex colors."""
    r1, g1, b1 = hex_to_rgb(start)
    r2, g2, b2 = hex_to_rgb(end)
    colors = []
    for i in range(steps):
        t = i / max(steps - 1, 1)
        r = int(r1 + (r2 - r1) * t)
        g = int(g1 + (g2 - g1) * t)
        b = int(b1 + (b2 - b1) * t)
        colors.append(rgb_to_hex(r, g, b))
    return colors
