"""Poly Haven — CC0 текстуры, HDRI и 3D-модели."""

from __future__ import annotations

from urllib.parse import urlparse

from ..models import Asset, File

NAME = "polyhaven"
TITLE = "Poly Haven (CC0 textures / HDRI / models)"
API = "https://api.polyhaven.com"
CDN_THUMB = "https://cdn.polyhaven.com/asset_img/thumbs/{id}.png?width=320&height=320"
TYPES = {"textures": "textures", "hdris": "hdris", "models": "models"}
PRIMARY = {"textures": "Diffuse", "hdris": "hdri", "models": "gltf"}
DEFAULT_FORMAT = {"textures": "jpg", "hdris": "hdr", "models": "gltf"}


def _kind(asset_type: str) -> str:
    return asset_type if asset_type in TYPES else "textures"


def search(session, query: str, limit: int = 10, type: str = "textures", **_) -> list[Asset]:
    kinds = list(TYPES) if type in ("all", "") else [_kind(type)]
    tokens = [t for t in query.lower().split() if t]
    found: list[tuple[float, str, dict, str]] = []

    for kind in kinds:
        res = session.get(f"{API}/assets", params={"t": kind}, timeout=60)
        res.raise_for_status()
        data = res.json()
        for asset_id, item in data.items():
            hay = " ".join(
                [
                    asset_id,
                    item.get("name", ""),
                    " ".join(item.get("tags", []) or []),
                    " ".join(item.get("categories", []) or []),
                ]
            ).lower()
            if not all(token in hay for token in tokens):
                continue
            score = 0.0
            name = item.get("name", "").lower()
            for token in tokens:
                if token in name:
                    score += 3
                if token in asset_id:
                    score += 2
                if token in (item.get("tags") or []):
                    score += 1
            found.append((score, asset_id, item, kind))

    found.sort(key=lambda row: (-row[0], row[2].get("name", "")))
    result: list[Asset] = []
    for _score, asset_id, item, kind in found[:limit]:
        authors = item.get("authors") or {}
        author = ", ".join(authors.keys()) if isinstance(authors, dict) else str(authors)
        result.append(
            Asset(
                source=NAME,
                id=asset_id,
                title=item.get("name") or asset_id,
                page=f"https://polyhaven.com/a/{asset_id}",
                thumbnail=CDN_THUMB.format(id=asset_id),
                author=author,
                license="CC0",
                tags=(item.get("tags") or [])[:8],
                extra={"kind": kind, "max_resolution": item.get("max_resolution")},
            )
        )
    return result


def from_url(url: str) -> Asset | None:
    if "polyhaven.com/a/" not in url:
        return None
    asset_id = urlparse(url).path.rstrip("/").rsplit("/", 1)[-1]
    return Asset(
        source=NAME,
        id=asset_id,
        title=asset_id.replace("_", " ").title(),
        page=f"https://polyhaven.com/a/{asset_id}",
        license="CC0",
        extra={"kind": "textures"},
    )


def resolve(
    session,
    asset: Asset,
    resolution: str = "1k",
    format: str = "",
    all_maps: bool = False,
    **_,
) -> list[File]:
    res = session.get(f"{API}/files/{asset.id}", timeout=60)
    res.raise_for_status()
    data = res.json()
    kind = asset.extra.get("kind") or "textures"
    fmt = format or DEFAULT_FORMAT.get(kind, "jpg")

    files: list[File] = []
    categories = list(data.keys()) if all_maps else [PRIMARY.get(kind, "Diffuse")]
    categories = [c for c in categories if c in data] or list(data.keys())[:1]

    for category in categories:
        by_res = data.get(category) or {}
        if not isinstance(by_res, dict):
            continue
        available_res = list(by_res.keys())
        chosen_res = resolution if resolution in by_res else next(
            (r for r in ("1k", "2k", "4k", "8k", "512") if r in by_res),
            available_res[0] if available_res else "",
        )
        if not chosen_res:
            continue
        formats = by_res.get(chosen_res) or {}
        if not isinstance(formats, dict):
            continue
        chosen_fmt = fmt if fmt in formats else next(iter(formats), "")
        info = formats.get(chosen_fmt) or {}
        url = info.get("url") if isinstance(info, dict) else ""
        if not url:
            continue
        ext = "." + chosen_fmt if not chosen_fmt.startswith(".") else chosen_fmt
        filename = f"{asset.id}_{category}_{chosen_res}{ext}"
        files.append(
            File(
                url=url,
                label=f"{category} {chosen_res} {chosen_fmt}",
                filename=filename,
                referer=asset.page,
                size=int(info.get("size") or 0),
            )
        )
    if not files:
        raise RuntimeError("Poly Haven: не нашёл файлов для выбранного разрешения/формата")
    return files
