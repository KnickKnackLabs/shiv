"""Pluggable renderer registry."""

from __future__ import annotations

from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from .base import BaseRenderer

_REGISTRY: dict[str, type[BaseRenderer]] = {}


def register(name: str):
    """Decorator to register a renderer class."""
    def decorator(cls: type[BaseRenderer]):
        _REGISTRY[name] = cls
        return cls
    return decorator


def get_renderer(name: str) -> type[BaseRenderer]:
    """Look up a renderer by name. Auto-imports built-in renderers."""
    if not _REGISTRY:
        _import_builtins()
    if name not in _REGISTRY:
        available = ", ".join(sorted(_REGISTRY.keys()))
        raise KeyError(f"Unknown renderer '{name}'. Available: {available}")
    return _REGISTRY[name]


def list_renderers() -> list[str]:
    """List available renderer names."""
    if not _REGISTRY:
        _import_builtins()
    return sorted(_REGISTRY.keys())


def _import_builtins():
    """Import all built-in renderer modules to trigger registration."""
    from . import grid  # noqa: F401
