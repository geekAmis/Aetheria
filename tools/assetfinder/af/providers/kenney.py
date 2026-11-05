"""Kenney.nl — CC0 game assets."""

from __future__ import annotations

import re
from urllib.parse import quote_plus, urljoin, urlparse

from bs4 import BeautifulSoup

from ..models import Asset, File

NAME = "kenney"
TITLE = "Kenney (CC0 game assets)"
SITE = "https://kenney.nl"


def _asset_links(soup: BeautifulSoup):
    for card in soup.select("div.asset"):
        link = None
        for a in card.find_all("a", href=True):
            href = a["href"]
            if "/assets/" in href and not re.search(r"(category|tag|series):", href):
                link = a
                break
        if link:
            yield card, link


def search(session, query: str, limit: int = 10, **_) -> list[Asset]:
    url = f"{SITE}/assets?q={quote_plus(query)}"
    res = session.get(url, timeout=45)
    res.raise_for_status()
    soup = BeautifulSoup(res.text, "html.parser")

    result: list[Asset] = []
    seen: set[str] = set()
    for card, link in _asset_links(soup):
        page = urljoin(SITE, link["href"])
        if page in seen:
            continue
        seen.add(page)
        title_el = card.select_one("h2")
        title = (title_el.get_text(" ", strip=True) if title_el else link.get_text(" ", strip=True)) or page
        cover = card.select_one(".cover")
        thumb = ""
        if cover and cover.get("style"):
            m = re.search(r"url\(['\"]?([^'\")]+)", cover["style"])
            if m:
                thumb = urljoin(SITE, m.group(1))
        tags = [a.get_text(" ", strip=True) for a in card.select("span.bold a")]
        result.append(
            Asset(
                source=NAME,
                id=page.rstrip("/").rsplit("/", 1)[-1],
                title=title,
                page=page,
                thumbnail=thumb,
                author="Kenney",
                license="CC0",
                tags=[t for t in tags if t],
            )
        )
        if len(result) >= limit:
            break
    return result


def from_url(url: str) -> Asset | None:
    if "kenney.nl/assets/" not in url:
        return None
    slug = urlparse(url).path.rstrip("/").rsplit("/", 1)[-1]
    if not slug or re.search(r"(category|tag|series):", slug):
        return None
    return Asset(
        source=NAME,
        id=slug,
        title=slug.replace("-", " ").title(),
        page=f"{SITE}/assets/{slug}",
        author="Kenney",
        license="CC0",
    )


def resolve(session, asset: Asset, **_) -> list[File]:
    res = session.get(asset.page, timeout=45, headers={"Referer": f"{SITE}/assets"})
    res.raise_for_status()
    soup = BeautifulSoup(res.text, "html.parser")

    if not asset.thumbnail:
        cover = soup.select_one(".cover")
        if cover and cover.get("style"):
            m = re.search(r"url\(['\"]?([^'\")]+)", cover["style"])
            if m:
                asset.thumbnail = urljoin(SITE, m.group(1))

    el = soup.find(attrs={"data-download-id": True})
    if not el:
        m = re.search(r"data-download-id=['\"]([0-9a-f]+)['\"]", res.text)
        if not m:
            raise RuntimeError("не нашёл data-download-id на странице Kenney")
        download_id = m.group(1)
    else:
        download_id = el["data-download-id"]

    api = f"{SITE}/download-link/{download_id}"
    link_res = session.get(api, timeout=30, headers={"Referer": asset.page, "Accept": "application/json"})
    link_res.raise_for_status()
    data = link_res.json()
    url = data.get("url")
    if not url:
        raise RuntimeError(f"Kenney не вернул ссылку: {data}")
    name = f"{asset.id}.zip"
    return [File(url=url, label="zip", filename=name, referer=asset.page)]
