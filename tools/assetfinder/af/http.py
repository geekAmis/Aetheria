"""HTTP-сессия, cookie и загрузка файлов."""

from __future__ import annotations

import json
import os
import re
import time
from pathlib import Path
from typing import Iterable
from urllib.parse import unquote, urlparse

import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry

USER_AGENT = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:159.0) "
    "Gecko/20100101 Firefox/159.0"
)

ASSET_EXTENSIONS = (
    "zip", "rar", "7z", "tar", "gz", "tgz",
    "png", "jpg", "jpeg", "webp", "gif", "svg", "bmp", "tga", "psd",
    "ogg", "mp3", "wav", "flac", "m4a", "aac",
    "fbx", "obj", "glb", "gltf", "blend", "dae", "stl", "ply",
    "ttf", "otf", "woff", "woff2",
    "json", "tmx", "tsx", "csv",
)


def make_session(
    cookie: str = "",
    cookie_file: str = "",
    headers: dict[str, str] | None = None,
    retries: int = 3,
) -> requests.Session:
    session = requests.Session()
    retry = Retry(
        total=retries,
        connect=retries,
        read=retries,
        backoff_factor=0.7,
        status_forcelist=(429, 500, 502, 503, 504),
        allowed_methods=frozenset({"GET", "HEAD"}),
    )
    adapter = HTTPAdapter(max_retries=retry, pool_maxsize=8)
    session.mount("https://", adapter)
    session.mount("http://", adapter)
    session.headers.update(
        {
            "User-Agent": USER_AGENT,
            "Accept-Language": "ru-RU,ru;q=0.9,en-US;q=0.8,en;q=0.7",
            "Accept": "text/html,application/xhtml+xml,application/json;q=0.9,*/*;q=0.8",
        }
    )
    if headers:
        session.headers.update(headers)

    raw = cookie
    if not raw and cookie_file and os.path.exists(cookie_file):
        raw = Path(cookie_file).read_text(encoding="utf-8").strip()
    if raw:
        session.headers["Cookie"] = normalize_cookie(raw)
    return session


def normalize_cookie(raw: str) -> str:
    """Принимает строку 'a=b; c=d', JSON Cookie-Editor или Netscape cookies.txt."""
    text = raw.strip()
    if not text:
        return ""
    if text.startswith("["):
        try:
            data = json.loads(text)
            pairs = [f"{c['name']}={c['value']}" for c in data if c.get("name")]
            return "; ".join(pairs)
        except Exception:
            pass
    if "\t" in text:
        pairs = []
        for line in text.splitlines():
            if not line or line.startswith("#"):
                continue
            cols = line.split("\t")
            if len(cols) >= 7 and "craftpix" not in cols[0].lower():
                pairs.append(f"{cols[5].strip()}={cols[6].strip()}")
            elif len(cols) >= 7:
                pairs.append(f"{cols[5].strip()}={cols[6].strip()}")
        if pairs:
            return "; ".join(pairs)
    return " ".join(text.splitlines()).strip()


def get(session: requests.Session, url: str, **kwargs) -> requests.Response:
    kwargs.setdefault("timeout", 45)
    res = session.get(url, **kwargs)
    res.raise_for_status()
    return res


def head_size(session: requests.Session, url: str) -> int:
    try:
        res = session.head(url, timeout=20, allow_redirects=True)
        return int(res.headers.get("content-length") or 0)
    except Exception:
        return 0


def guess_extension(url: str) -> str:
    path = urlparse(url).path
    name = unquote(Path(path).name)
    if "." in name:
        return name.rsplit(".", 1)[-1].lower()
    return ""


def safe_filename(name: str, fallback: str = "file") -> str:
    name = unquote(name or "").strip().replace("\\", "/").split("/")[-1]
    name = re.sub(r'[<>:"/\\|?*\x00-\x1f]', "_", name)
    name = re.sub(r"\s+", " ", name).strip(" .")
    return name[:150] or fallback


def filename_from_response(res: requests.Response, url: str) -> str:
    cd = res.headers.get("content-disposition", "")
    if cd:
        star = re.search(r"filename\*\s*=\s*UTF-8''([^;]+)", cd, re.I)
        if star:
            return safe_filename(unquote(star.group(1).strip()))
        plain = re.search(r'filename\s*=\s*"?([^";]+)"?', cd, re.I)
        if plain:
            return safe_filename(plain.group(1).strip())
    name = unquote(Path(urlparse(url).path).name)
    if name:
        return safe_filename(name)
    ext = guess_extension(url) or "bin"
    return f"download.{ext}"


def human_size(num: float) -> str:
    if not num or num <= 0:
        return "0 B"
    for unit in ("B", "KB", "MB", "GB", "TB"):
        if num < 1024 or unit == "TB":
            return f"{num:.0f} {unit}" if unit == "B" else f"{num:.1f} {unit}"
        num /= 1024
    return f"{num:.1f} TB"


def download_file(
    session: requests.Session,
    url: str,
    out_dir: Path,
    referer: str = "",
    filename: str = "",
    max_bytes: int = 0,
    timeout: int = 120,
    quiet: bool = False,
) -> Path | None:
    """Скачивает URL в out_dir. Возвращает путь или None при ошибке."""
    out_dir.mkdir(parents=True, exist_ok=True)
    headers: dict[str, str] = {}
    if referer:
        headers["Referer"] = referer
        headers["Sec-Fetch-Dest"] = "document"
        headers["Sec-Fetch-Mode"] = "navigate"
        headers["Sec-Fetch-Site"] = "same-site"
        headers["Sec-Fetch-User"] = "?1"
    try:
        res = session.get(url, headers=headers, stream=True, timeout=timeout, allow_redirects=True)
    except Exception as exc:
        print(f"  ! {exc}")
        return None

    if res.status_code >= 400:
        print(f"  ! HTTP {res.status_code}: {url[:110]}")
        res.close()
        return None

    ctype = (res.headers.get("content-type") or "").lower()
    length = int(res.headers.get("content-length") or 0)
    if length and max_bytes and length > max_bytes:
        print(f"  ! пропуск: {human_size(length)} > лимита {human_size(max_bytes)}")
        res.close()
        return None
    if "text/html" in ctype and length and length < 80_000:
        body = res.text[:400].lstrip().lower()
        res.close()
        if "<html" in body or "<!doctype" in body or "cloudflare" in body:
            print(f"  ! сервер вернул HTML вместо файла: {url[:110]}")
            return None

    name = safe_filename(filename) if filename else filename_from_response(res, url)
    dest = out_dir / name
    if dest.exists():
        dest = out_dir / f"{dest.stem}-{int(time.time())}{dest.suffix}"

    part = dest.with_suffix(dest.suffix + ".part")
    written = 0
    try:
        with open(part, "wb") as fh:
            for chunk in res.iter_content(256 * 1024):
                if not chunk:
                    continue
                fh.write(chunk)
                written += len(chunk)
                if max_bytes and written > max_bytes:
                    raise ValueError(f"файл больше лимита {human_size(max_bytes)}")
        if length and written != length:
            raise ValueError(f"неполная загрузка: {written} из {length} байт")
        os.replace(part, dest)
    except Exception as exc:
        print(f"  ! {exc}")
        try:
            part.unlink(missing_ok=True)
        except Exception:
            pass
        res.close()
        return None
    finally:
        res.close()

    if not quiet:
        print(f"  ✓ {dest.name}  {human_size(written)}")
    return dest


def write_manifest(out_root: Path, entry: dict) -> None:
    out_root.mkdir(parents=True, exist_ok=True)
    with open(out_root / "manifest.jsonl", "a", encoding="utf-8") as fh:
        fh.write(json.dumps(entry, ensure_ascii=False) + "\n")


def cookie_dict(cookie_header: str) -> dict[str, str]:
    result: dict[str, str] = {}
    for part in (cookie_header or "").split(";"):
        if "=" in part:
            key, value = part.split("=", 1)
            key = key.strip()
            if key:
                result[key] = value.strip()
    return result

