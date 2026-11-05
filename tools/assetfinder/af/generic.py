"""Извлечение ссылок на файлы с произвольной страницы."""

from __future__ import annotations

import re
from urllib.parse import urljoin, urlparse

from bs4 import BeautifulSoup

from .http import ASSET_EXTENSIONS


def extension(url: str) -> str:
    path = urlparse(url).path
    name = path.rsplit("/", 1)[-1]
    return name.rsplit(".", 1)[-1].lower() if "." in name else ""


def is_asset(url: str, exts: set[str]) -> bool:
    if not url.lower().startswith(("http://", "https://")):
        return False
    ext = extension(url)
    return ext in exts


def extract_links(
    html: str,
    base_url: str,
    exts: set[str] | None = None,
    include_images: bool = False,
) -> list[str]:
    exts = exts or set(ASSET_EXTENSIONS)
    soup = BeautifulSoup(html, "html.parser")
    urls: list[str] = []
    seen: set[str] = set()

    def add(raw: str) -> None:
        if not raw or raw.startswith(("data:", "javascript:", "mailto:", "#")):
            return
        url = urljoin(base_url, raw)
        if url in seen:
            return
        if is_asset(url, exts):
            seen.add(url)
            urls.append(url)

    for a in soup.find_all("a", href=True):
        add(a["href"])
    if include_images:
        for img in soup.find_all(["img", "source"]):
            for attr in ("src", "data-src", "data-original"):
                if img.get(attr):
                    add(img[attr])
            if img.get("srcset"):
                for part in img["srcset"].split(","):
                    add(part.strip().split(" ")[0])

    return urls


def page_dir_name(url: str, fallback: str = "page") -> str:
    host = urlparse(url).netloc.replace(":", "_") or "site"
    slug = urlparse(url).path.rstrip("/").rsplit("/", 1)[-1] or fallback
    slug = re.sub(r"[^A-Za-z0-9._-]+", "-", slug).strip("-")
    return f"{host}__{slug or fallback}"
