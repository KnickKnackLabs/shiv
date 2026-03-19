"""Grid renderer — arranges colored shapes in a grid layout."""

from __future__ import annotations

from ..config import LogoConfig
from ..palettes import pick_colors
from ..svg import SvgDocument, SvgElement
from .base import BaseRenderer
from . import register


@register("grid")
class GridRenderer(BaseRenderer):
    """Renders a grid of colored shapes (squares, circles, or diamonds)."""

    def render(self) -> SvgDocument:
        cfg = self.config
        cols, rows = cfg.columns, cfg.rows
        gap = cfg.gap
        total_cells = cols * rows

        # Resolve colors
        if cfg.colors:
            colors = cfg.colors
            # Extend if not enough colors provided
            while len(colors) < total_cells:
                colors = colors + colors
            colors = colors[:total_cells]
        else:
            colors = pick_colors(total_cells, palette=cfg.palette, seed=cfg.seed)

        # Calculate cell size from canvas size
        canvas = cfg.size
        cell_w = (canvas - gap * (cols + 1)) / cols
        cell_h = (canvas - gap * (rows + 1)) / rows
        cell = min(cell_w, cell_h)

        # Recalculate actual canvas to keep it tight
        actual_w = cell * cols + gap * (cols + 1)
        actual_h = cell * rows + gap * (rows + 1)

        doc = SvgDocument(actual_w, actual_h)

        # Optional background
        if cfg.background:
            doc.rect(0, 0, actual_w, actual_h, fill=cfg.background)

        # Draw cells
        for i in range(total_cells):
            row, col = divmod(i, cols)
            x = gap + col * (cell + gap)
            y = gap + row * (cell + gap)
            color = colors[i]

            if cfg.shape == "circle":
                r = cell / 2
                doc.circle(x + r, y + r, r, fill=color)
            elif cfg.shape == "diamond":
                cx, cy = x + cell / 2, y + cell / 2
                half = cell / 2
                points = f"{cx},{cy - half} {cx + half},{cy} {cx},{cy + half} {cx - half},{cy}"
                doc.add(SvgElement("polygon", points=points, fill=color))
            else:
                # Square (default)
                doc.rect(x, y, cell, cell, rx=cfg.corner_radius, ry=cfg.corner_radius, fill=color)

        return doc
