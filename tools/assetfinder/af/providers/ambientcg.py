"""ambientCG — CC0 PBR-материалы, HDRI и 3D-ассеты."""

from __future__ import annotations

from urllib.parse import quote_plus, urlparse

from ..models import Asset, File

NAME = "ambientcg"
TITLE = "ambientCG (CC0 PBR materials / HDRI)"
API = "https://ambientcg.com/api/v2/full_json"
SITE = "https://ambientcg.com"
DEFAULT_ATTRIBUTE = "1K-JPG"


def search(
    session,
    query: str,
    limit: int = 10,
    type: str = "Material",
    **_) -> list[Asset]:
    params = {
        "type": type or "Material",
        "limit": str(max(1, limit)),
        "q": query,
        "include": "downloadData,previewData,labelData",
    }
    res = session.get(API, params=params, timeout=60)
    res.raise_for_status()
    data = res.json()

    result: list[Asset] = []
    for item in data.get("foundAssets", []):
        asset_id = item.get("assetId") or ""
        if not asset_id:
            continue
        thumb = item.get("previewImage") or ""
        if isinstance(thumb, dict):
            thumb = thumb.get("url") or thumb.get("previewImage") or ""
        downloads = _downloads(item)
        result.append(
            Asset(
                source=NAME,
                id=asset_id,
                title=item.get("displayName") or item.get("customDisplayName") or asset_id,
                page=item.get("shortLink") or f"{SITE}/a/{asset_id}",
                thumbnail=thumb,
                author="ambientCG",
                license="CC0",
                tags=(item.get("tags") or [])[:8],
                downloads=downloads,
                extra={"type": item.get("dataType"), "category": item.get("displayCategory")},
            )
        )
    return result


def _downloads(item: dict) -> list[File]:
    folders = item.get("downloadFolders") or {}
    files: list[File] = []
    for folder in folders.values():
        cats = (folder or {}).get("downloadFiletypeCategories") or {}
        for category in cats.values():
            for dl in (category or {}).get("downloads", []) or []:
                url = dl.get("downloadLink") or dl.get("fullDownloadPath")
                if not url:
                    continue
                attr = dl.get("attribute") or dl.get("filetype") or "file"
                files.append(
                    File(
                        url=url,
                        label=attr,
                        filename=dl.get("fileName") or "",
                        referer=SITE + "/",
                        size=int(dl.get("size") or 0),
                    )
                )
    return files


def from_url(url: str) -> Asset | None:
    if "ambientcg.com" not in url:
        return None
    path = urlparse(url).path.rstrip("/")
    asset_id = path.rsplit("/", 1)[-1]
    if not asset_id or asset_id in ("a", "view", "assets"):
        return None
    return Asset(
        source=NAME,
        id=asset_id,
        title=asset_id,
        page=f"{SITE}/a/{asset_id}",
        author="ambientCG",
        license="CC0",
    )


def resolve(
    session,
    asset: Asset,
    attribute: str = DEFAULT_ATTRIBUTE,
    **_,
) -> list[File]:
    if asset.downloads:
        files = asset.downloads
    else:
        res = session.get(
            API,
            params={
                "type": "Material",
                "assetId": asset.id,
                "include": "downloadData,previewData,labelData",
            },
            timeout=60,
        )
        res.raise_for_status()
        found = res.json().get("foundAssets") or []
        match = next(
            (x for x in found if str(x.get("assetId", "")).lower() == asset.id.lower()),
            None,
        )
        if not match:
            raise RuntimeError(f"ambientCG: ассет {asset.id} не найден")
        asset.title = match.get("displayName") or asset.title
        files = _downloads(match)

    preferred = [f for f in files if attribute.lower() in (f.label or "").lower()]
    chosen = preferred or files
    if not chosen:
        raise RuntimeError("ambientCG: нет ссылок на скачивание")
    return chosen[:1] if preferred else chosen[:1]
