"""Base renderer interface."""

from __future__ import annotations

from abc import ABC, abstractmethod

from ..config import LogoConfig
from ..svg import SvgDocument


class BaseRenderer(ABC):
    """Abstract base for all logo renderers."""

    def __init__(self, config: LogoConfig):
        self.config = config

    @abstractmethod
    def render(self) -> SvgDocument:
        """Produce an SVG document from the config."""

    def render_string(self) -> str:
        """Render to SVG string."""
        return self.render().render()
