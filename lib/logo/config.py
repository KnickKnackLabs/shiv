"""Config loading and validation for logo generation."""

from __future__ import annotations

import json
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Optional


@dataclass
class LogoConfig:
    """Configuration for logo generation."""

    # Renderer selection
    renderer: str = "grid"

    # Canvas
    size: int = 512
    background: Optional[str] = None

    # Grid-specific
    columns: int = 5
    rows: int = 5
    gap: float = 4
    corner_radius: float = 6
    shape: str = "square"  # "square" | "circle" | "diamond"

    # Colors
    colors: list[str] = field(default_factory=list)
    palette: str = "vivid"

    # Seed for reproducible randomness
    seed: Optional[int] = None

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> LogoConfig:
        known = {f.name for f in cls.__dataclass_fields__.values()}
        filtered = {k: v for k, v in data.items() if k in known}
        return cls(**filtered)

    @classmethod
    def from_file(cls, path: str | Path) -> LogoConfig:
        with open(path) as f:
            return cls.from_dict(json.load(f))

    def to_dict(self) -> dict[str, Any]:
        from dataclasses import asdict
        return asdict(self)
