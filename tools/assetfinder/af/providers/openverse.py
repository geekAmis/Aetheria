"""Openverse — поиск CC-изображений (фото, текстуры, референсы)."""

from __future__ import annotations

import requests

from ..http import USER_AGENT
from ..models import Asset, File

NAME = "openverse"
TITLE = "Openverse (CC images)"
API = "https://api.openverse.org/v1/images/"


def search(session, query: str, limit: int = 10, **_) -> list[Asset]:
    # Openverse периодически отвечает 504; не тратим минуты на ретраи.
    res = requests.get(
        API,
        params={
            "q": query,
            "page_size": max(1, min(limit, 50)),
            "license_type": "commercial",
        },
        headers={"User-Agent": USER_AGENT},
        timeout=12,
    )
    if res.status_code >= 500:
        raise RuntimeError(f"Openverse временно недоступен (HTTP {res.status_code})")
    res.raise_for_status()
    data = res.json()
    result: list[Asset] = []
    for item in data.get("results", []):
        url = item.get("url") or ""
        if not url:
            continue
        lic = item.get("license") or ""
        version = item.get("license_version") or ""
        result.append(
            Asset(
                source=NAME,
                id=str(item.get("id") or url.rsplit("/", 1)[-1]),
                title=item.get("title") or item.get("foreign_landing_url") or url,
                page=item.get("foreign_landing_url") or url,
                thumbnail=item.get("thumbnail") or "",
                author=item.get("creator") or "",
                license=(f"{lic} {version}".strip() or "CC"),
                tags=(item.get("tags") or [])[:8],
                downloads=[
                    File(
                        url=url,
                        label="image",
                        filename=url.rsplit("/", 1)[-1].split("?")[0],
                        referer=item.get("foreign_landing_url") or "",
                    )
                ],
            )
        )
    return result


def from_url(url: str) -> Asset | None:
    return None
