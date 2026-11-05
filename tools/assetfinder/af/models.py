"""Общие модели данных для assetfinder."""

from __future__ import annotations

from dataclasses import dataclass, field, asdict
from typing import Any


@dataclass
class File:
    """Один скачиваемый файл."""

    url: str
    label: str = ""
    filename: str = ""
    referer: str = ""
    size: int = 0

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


@dataclass
class Asset:
    """Нормализованный результат поиска."""

    source: str
    id: str
    title: str
    page: str
    thumbnail: str = ""
    author: str = ""
    license: str = ""
    tags: list[str] = field(default_factory=list)
    downloads: list[File] = field(default_factory=list)
    note: str = ""
    extra: dict[str, Any] = field(default_factory=dict)

    def to_dict(self) -> dict[str, Any]:
        data = asdict(self)
        data["downloads"] = [f.to_dict() for f in self.downloads]
        return data

    @property
    def slug(self) -> str:
        from urllib.parse import urlparse

        parts = [p for p in urlparse(self.page).path.split("/") if p]
        if parts:
            return parts[-1]
        return self.id or "asset"
