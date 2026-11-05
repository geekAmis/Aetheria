#!/usr/bin/env python3
"""assetfinder — быстрый поиск и скачивание игровых ассетов.

Источники:
  kenney       — CC0 2D/3D/audio, https://kenney.nl
  opengameart  — свободные ассеты, https://opengameart.org
  polyhaven    — CC0 текстуры, HDRI, модели, https://polyhaven.com
  ambientcg    — CC0 PBR-материалы и HDRI, https://ambientcg.com
  openverse    — CC-изображения, https://openverse.org

Примеры:
  python assetfinder.py search "pixel forest" --sources kenney,opengameart
  python assetfinder.py search "wood" --sources ambientcg --download
  python assetfinder.py download https://kenney.nl/assets/mini-shop
  python assetfinder.py grab https://example.com/page --ext zip,png --browser
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import urlparse

from af import browser, generic
from af.http import (
    ASSET_EXTENSIONS,
    cookie_dict,
    download_file,
    make_session,
    safe_filename,
    write_manifest,
)
from af.models import Asset, File
from af.providers import DEFAULT_SOURCES, PROVIDERS, get, names

VERSION = "1.0"


def log(*args, **kwargs):
    print(*args, **kwargs)


def warn(*args):
    print("!", *args, file=sys.stderr)


def build_parser() -> argparse.ArgumentParser:
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--cookie", default="", help="cookie строкой 'a=b; c=d'")
    common.add_argument("--cookie-file", default="cookies.txt", help="файл с cookie")
    common.add_argument(
        "--header", action="append", default=[], metavar="K: V", help="доп. заголовок (можно несколько)"
    )
    common.add_argument("--delay", type=float, default=0.4, help="пауза между файлами, сек")
    common.add_argument("--max-size", type=float, default=0, help="лимит размера файла, МБ (0 = без лимита)")
    common.add_argument("--dry-run", action="store_true", help="показать ссылки, но не скачивать")
    common.add_argument("--quiet", action="store_true")

    parser = argparse.ArgumentParser(
        prog="assetfinder",
        description="Поиск и скачивание бесплатных игровых ассетов.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument("--version", action="version", version=f"assetfinder {VERSION}")
    sub = parser.add_subparsers(dest="cmd", required=True)

    p_search = sub.add_parser("search", parents=[common], help="поиск по каталогам")
    p_search.add_argument("query", nargs="+", help="поисковый запрос")
    p_search.add_argument(
        "--sources",
        default=",".join(DEFAULT_SOURCES),
        help=f"через запятую: {', '.join(names())} (по умолчанию {','.join(DEFAULT_SOURCES)})",
    )
    p_search.add_argument("--limit", type=int, default=10, help="результатов на источник")
    p_search.add_argument("--download", action="store_true", help="скачать найденное")
    p_search.add_argument("--json", action="store_true", help="вывести JSON")
    add_asset_options(p_search)

    p_dl = sub.add_parser("download", parents=[common], help="скачать ассет по URL страницы")
    p_dl.add_argument("url")
    p_dl.add_argument("--browser", action="store_true", help="отрендерить страницу в Firefox (geckodriver)")
    p_dl.add_argument("--images", action="store_true", help="учитывать <img>/srcset")
    p_dl.add_argument("--headed", action="store_true", help="показать окно браузера")
    p_dl.add_argument("--wait", type=float, default=4.0, help="ожидание после загрузки страницы, сек")
    p_dl.add_argument("--click", default="", help="CSS-селекторы кнопок для клика (через запятую)")
    add_asset_options(p_dl)

    p_grab = sub.add_parser("grab", parents=[common], help="собрать файлы со страницы")
    p_grab.add_argument("url")
    p_grab.add_argument("--out", default="downloads")
    p_grab.add_argument("--ext", default="", help="расширения через запятую (по умолчанию все поддерживаемые)")
    p_grab.add_argument("--limit", type=int, default=50, help="максимум файлов (0 = все)")
    p_grab.add_argument("--images", action="store_true", help="учитывать <img>/srcset")
    p_grab.add_argument("--browser", action="store_true", help="отрендерить страницу в Firefox")
    p_grab.add_argument("--click", default="", help="CSS-селекторы кнопок для клика (через запятую)")
    p_grab.add_argument("--headed", action="store_true", help="показать окно браузера")
    p_grab.add_argument("--wait", type=float, default=4.0, help="ожидание после загрузки страницы, сек")

    sub.add_parser("sources", help="список источников")
    return parser


def add_asset_options(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--resolution", default="1k", help="1k/2k/4k/8k (polyhaven)")
    parser.add_argument("--format", default="", help="jpg/png/exr/hdr/gltf (polyhaven)")
    parser.add_argument("--all-maps", action="store_true", help="все карты текстуры (polyhaven)")
    parser.add_argument("--attribute", default="1K-JPG", help="вариант архива ambientCG")
    parser.add_argument("--type", default="", help="textures|hdris|models|all (polyhaven) или Material|HDRI (ambientcg)")
    parser.add_argument("--out", default="downloads", help="папка загрузок")


def make_http(args):
    headers: dict[str, str] = {}
    for item in getattr(args, "header", []) or []:
        if ":" in item:
            key, value = item.split(":", 1)
            headers[key.strip()] = value.strip()
    return make_session(
        cookie=getattr(args, "cookie", ""),
        cookie_file=getattr(args, "cookie_file", ""),
        headers=headers,
    )


def max_bytes(args) -> int:
    size = float(getattr(args, "max_size", 0) or 0)
    return int(size * 1024 * 1024) if size > 0 else 0


def print_asset(index: int, asset: Asset) -> None:
    tags = ", ".join(asset.tags[:5])
    meta = " · ".join(x for x in (asset.license, asset.author) if x)
    print(f"[{index}] {asset.source:<11} {asset.title}")
    line = f"    {meta}"
    if tags:
        line += f"  [{tags}]"
    print(line)
    print(f"    {asset.page}")


def print_sources() -> None:
    rows = [
        ("kenney", "Kenney — CC0 2D/3D/audio", "https://kenney.nl/assets"),
        ("opengameart", "OpenGameArt — 2D/3D/audio, разные лицензии", "https://opengameart.org"),
        ("polyhaven", "Poly Haven — CC0 textures/HDRI/models", "https://polyhaven.com"),
        ("ambientcg", "ambientCG — CC0 PBR materials/HDRI", "https://ambientcg.com"),
        ("openverse", "Openverse — CC images", "https://openverse.org"),
    ]
    print(f"{'источник':<14} {'что ищем':<44} сайт")
    print("-" * 90)
    for name, desc, site in rows:
        print(f"{name:<14} {desc:<44} {site}")
    print("\nПоиск: assetfinder.py search \"...\" --sources kenney,opengameart")
    print("Скачивание: assetfinder.py download <URL страницы> --out downloads")
    print("Любая страница: assetfinder.py grab <URL> --ext zip,png --browser")


def cmd_search(args) -> int:
    query = " ".join(args.query).strip()
    sources = [s.strip().lower() for s in args.sources.split(",") if s.strip()]
    unknown = [s for s in sources if not get(s)]
    for name in unknown:
        warn(f"неизвестный источник: {name}")
    sources = [s for s in sources if get(s)]
    if not sources:
        warn("не выбрано ни одного источника")
        return 2

    session = make_http(args)
    results: list[Asset] = []
    for name in sources:
        provider = get(name)
        try:
            items = provider.search(
                session,
                query,
                limit=max(1, args.limit),
                type=args.type,
            )
        except Exception as exc:
            warn(f"{name}: {exc}")
            continue
        if not args.quiet and not args.json:
            print(f"— {provider.TITLE}: {len(items)}")
        results.extend(items)

    if args.json:
        print(json.dumps([a.to_dict() for a in results], ensure_ascii=False, indent=2))
    else:
        print()
        if not results:
            print("Ничего не найдено.")
        for i, asset in enumerate(results, 1):
            print_asset(i, asset)
        print(f"\nВсего: {len(results)}")

    if args.download and results:
        out = Path(args.out)
        print(f"\nСкачиваю в {out.resolve()} …")
        for asset in results:
            save_asset(session, asset, args, out)
    return 0


def cmd_download(args) -> int:
    session = make_http(args)
    url = args.url.strip()
    out = Path(args.out)

    provider = get_provider_for_url(url)
    if provider and not args.browser:
        asset = provider.from_url(url)
        if not asset:
            warn("не удалось разобрать URL")
            return 2
        return 0 if save_asset(session, asset, args, out) else 1

    if generic.is_asset(url, set(ASSET_EXTENSIONS)):
        files = [File(url=url, label=generic.extension(url), referer=url)]
        asset = Asset("direct", url, url.rsplit("/", 1)[-1], url, extra={"dir": ""})
        return 0 if save_files(session, asset, files, args, out) else 1

    # Неизвестный сайт — собираем ссылки со страницы.
    return grab_page(session, url, args, out, limit=50)


def cmd_grab(args) -> int:
    session = make_http(args)
    out = Path(args.out)
    exts = {e.strip().lower() for e in args.ext.split(",") if e.strip()} if args.ext else set(ASSET_EXTENSIONS)
    return grab_page(session, args.url, args, out, limit=args.limit, exts=exts)


def get_provider_for_url(url: str):
    for provider in PROVIDERS.values():
        if hasattr(provider, "from_url"):
            try:
                if provider.from_url(url):
                    return provider
            except Exception:
                continue
    return None


def grab_page(session, url: str, args, out: Path, limit: int = 50, exts=None) -> int:
    exts = exts or set(ASSET_EXTENSIONS)
    html = ""
    links: list[str] = []

    if getattr(args, "browser", False):
        click = [s.strip() for s in getattr(args, "click", "").split(",") if s.strip()]
        print(f"→ открываю в Firefox: {url}")
        html, links = browser.render(
            url,
            wait=getattr(args, "wait", 4.0),
            headless=not getattr(args, "headed", False),
            click=click,
            cookies=cookie_dict(session.headers.get("Cookie", "")),
        )
        links = [u for u in links if generic.is_asset(u, exts)]
        if getattr(args, "images", False):
            links.extend(generic.extract_links(html, url, exts, include_images=True))
        links = list(dict.fromkeys(links))
    else:
        res = session.get(url, timeout=45)
        res.raise_for_status()
        html = res.text
        links = generic.extract_links(html, url, exts, include_images=getattr(args, "images", False))

    if limit and limit > 0:
        links = links[:limit]

    print(f"Найдено файлов: {len(links)}")
    if not links:
        warn("на странице нет ссылок на файлы (попробуйте --browser или другие --ext)")
        return 1

    dest = out / generic.page_dir_name(url)
    asset = Asset(
        source="grab",
        id=url,
        title=url,
        page=url,
        downloads=[File(url=u, label=generic.extension(u), referer=url) for u in links],
        extra={"dir": generic.page_dir_name(url)},
    )
    return 0 if save_files(session, asset, asset.downloads, args, out) else 1


def save_asset(session, asset: Asset, args, out: Path) -> bool:
    provider = get(asset.source)
    files: list[File] = []
    if provider and hasattr(provider, "resolve"):
        try:
            files = provider.resolve(
                session,
                asset,
                resolution=getattr(args, "resolution", "1k"),
                format=getattr(args, "format", ""),
                all_maps=getattr(args, "all_maps", False),
                attribute=getattr(args, "attribute", "1K-JPG"),
                type=getattr(args, "type", ""),
            )
        except Exception as exc:
            warn(f"{asset.source}: {exc}")
            return False
    if not files:
        files = asset.downloads
    if not files:
        warn(f"{asset.title}: нет файлов для скачивания")
        return False
    return save_files(session, asset, files, args, out)


def save_files(session, asset: Asset, files: list[File], args, out: Path) -> bool:
    dest = out / asset.source
    extra = asset.extra or {}
    if "dir" in extra:
        dir_name = extra["dir"]
    else:
        dir_name = asset.slug or asset.id or "asset"
    if dir_name:
        dest = dest / safe_filename(dir_name)
    print(f"\n[{asset.source}] {asset.title}")
    if asset.license:
        print(f"  лицензия: {asset.license}" + (f" · автор: {asset.author}" if asset.author else ""))
    print(f"  страница: {asset.page}")

    saved: list[str] = []
    for file in files:
        if getattr(args, "dry_run", False):
            print(f"  · {file.label or 'file'}: {file.url}")
            continue
        path = download_file(
            session,
            file.url,
            dest,
            referer=file.referer or asset.page,
            filename=file.filename,
            max_bytes=max_bytes(args),
            quiet=getattr(args, "quiet", False) or getattr(args, "json", False),
        )
        if path:
            saved.append(str(path))
        time.sleep(max(0.0, getattr(args, "delay", 0.4)))

    if saved and not getattr(args, "dry_run", False):
        write_manifest(
            out,
            {
                "source": asset.source,
                "title": asset.title,
                "page": asset.page,
                "license": asset.license,
                "author": asset.author,
                "thumbnail": asset.thumbnail,
                "tags": asset.tags,
                "files": saved,
                "downloaded_at": datetime.now(timezone.utc).isoformat(),
            },
        )
    return bool(saved) or bool(getattr(args, "dry_run", False))


def main(argv=None) -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
        sys.stderr.reconfigure(encoding="utf-8", errors="replace")

    parser = build_parser()
    args = parser.parse_args(argv)

    if args.cmd == "sources":
        print_sources()
        return 0
    if args.cmd == "search":
        return cmd_search(args)
    if args.cmd == "download":
        return cmd_download(args)
    if args.cmd == "grab":
        return cmd_grab(args)
    parser.print_help()
    return 2


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        print("\nПрервано.")
        raise SystemExit(130)
