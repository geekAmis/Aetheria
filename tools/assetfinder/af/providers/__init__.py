"""Реестр провайдеров."""

from __future__ import annotations

from . import ambientcg, kenney, opengameart, openverse, polyhaven

PROVIDERS = {
    kenney.NAME: kenney,
    opengameart.NAME: opengameart,
    polyhaven.NAME: polyhaven,
    ambientcg.NAME: ambientcg,
    openverse.NAME: openverse,
}

DEFAULT_SOURCES = ["kenney", "opengameart", "polyhaven", "ambientcg"]


def get(name: str):
    return PROVIDERS.get(name.strip().lower())


def names() -> list[str]:
    return list(PROVIDERS)
