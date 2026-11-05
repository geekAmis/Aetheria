"""OpenGameArt.org — свободные 2D/3D/аудио ассеты."""

from __future__ import annotations

import re
from urllib.parse import quote_plus, urljoin

from bs4 import BeautifulSoup

from ..models import Asset, File

NAME = "opengameart"
TITLE = "OpenGameArt.org"
SITE = "https://opengameart.org"
FILE_EXTS = (
    "zip", "rar", "7z", "png", "jpg", "jpeg", "webp", "gif", "svg",
    "ogg", "mp3", "wav", "flac", "blend", "obj", "fbx", "glb", "gltf", "ttf",
)
ARCHIVES = {"zip", "rar", "7z"}
SKIP_SLUGS = {"faq", "art-challenge", "forumtopic"}


def _is_content_link(href: str) -> bool:
    if not href.startswith("/content/"):
        return False
    slug = href.rstrip("/").rsplit("/", 1)[-1].lower()
    if slug in SKIP_SLUGS:
        return False
    return not any(word in slug for word in ("challenge", "forum", "faq"))


def _ext(url: str) -> str:
    path = url.split("?")[0].split("#")[0]
    return path.rsplit(".", 1)[-1].lower() if "." in path.rsplit("/", 1)[-1] else ""


def search(session, query: str, limit: int = 10, **_) -> list[Asset]:
    url = f"{SITE}/art-search-advanced?keys={quote_plus(query)}"
    res = session.get(url, timeout=45)
    res.raise_for_status()
    soup = BeautifulSoup(res.text, "html.parser")

    result: list[Asset] = []
    seen: set[str] = set()
    for row in soup.select(".views-row"):
        link = None
        for a in row.find_all("a", href=True):
            if _is_content_link(a["href"]):
                link = a
                break
        if not link:
            continue
        page = urljoin(SITE, link["href"])
        if page in seen:
            continue
        seen.add(page)
        title = link.get_text(" ", strip=True) or page
        img = row.find("img")
        thumb = ""
        if img:
            thumb = urljoin(SITE, img.get("src") or img.get("data-src") or "")
        result.append(
            Asset(
                source=NAME,
                id=page.rstrip("/").rsplit("/", 1)[-1],
                title=title,
                page=page,
                thumbnail=thumb,
                license="см. страницу",
                tags=[],
            )
        )
        if len(result) >= limit:
            break
    return result


def from_url(url: str) -> Asset | None:
    if "opengameart.org/content/" not in url:
        return None
    slug = url.split("?")[0].rstrip("/").rsplit("/", 1)[-1]
    return Asset(
        source=NAME,
        id=slug,
        title=slug.replace("-", " ").title(),
        page=f"{SITE}/content/{slug}",
        license="см. страницу",
    )


def _license(soup: BeautifulSoup) -> str:
    for tag in soup.find_all(["div", "span", "td", "p", "li"]):
        text = tag.get_text(" ", strip=True)
        if text.startswith("License(s)") and len(text) < 300:
            value = text[len("License(s)"):].lstrip(": ").split("Collections")[0].strip()
            if value:
                return value
    return ""


def resolve(session, asset: Asset, **_) -> list[File]:
    res = session.get(asset.page, timeout=45)
    res.raise_for_status()
    soup = BeautifulSoup(res.text, "html.parser")

    if not asset.license or asset.license == "см. страницу":
        asset.license = _license(soup) or "см. страницу"
    author_el = soup.select_one("a.username") or soup.select_one("[rel='author']")
    if author_el:
        asset.author = author_el.get_text(" ", strip=True)
    if not asset.thumbnail:
        img = soup.select_one("img[typeof='foaf:Image']") or soup.select_one(".field-name-field-art-image img")
        if img:
            asset.thumbnail = urljoin(SITE, img.get("src") or "")

    found: list[tuple[str, str]] = []
    seen: set[str] = set()
    for a in soup.find_all("a", href=True):
        href = a["href"]
        if "/sites/default/files/" not in href:
            continue
        if "/styles/" in href or href.endswith(".part"):
            continue
        ext = _ext(href)
        if ext not in FILE_EXTS:
            continue
        url = urljoin(SITE, href)
        if url in seen:
            continue
        seen.add(url)
        found.append((url, a.get_text(" ", strip=True) or url.rsplit("/", 1)[-1]))

    archives = [item for item in found if _ext(item[0]) in ARCHIVES]
    files = archives or found
    return [
        File(url=url, label=_ext(url), filename=url.rsplit("/", 1)[-1], referer=asset.page)
        for url, _label in files[:20]
    ]
