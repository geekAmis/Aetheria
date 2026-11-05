# assetfinder

Поиск и скачивание бесплатных игровых ассетов из нескольких каталогов одной
командой. Python + `requests` + `BeautifulSoup`; для JS-страниц — Selenium и
Firefox/geckodriver.

```
python assetfinder.py search "pixel forest" --sources kenney,opengameart
python assetfinder.py download https://kenney.nl/assets/mini-shop
python assetfinder.py grab https://example.com/page --ext zip,png --browser
```

## Источники

| Источник | Что внутри | Лицензия |
|---|---|---|
| `kenney` | 2D/3D/audio, готовые паки | CC0 |
| `opengameart` | спрайты, тайлсеты, музыка, 3D | разная (CC0/CC-BY/GPL) |
| `polyhaven` | текстуры, HDRI, 3D-модели | CC0 |
| `ambientcg` | PBR-материалы, HDRI | CC0 |
| `openverse` | фото, текстуры, референсы | CC (см. результат) |

Лицензия и автор пишутся в `manifest.jsonl` рядом с загрузками — это удобно для
соблюдения атрибуции.

## Установка

Нужен Python 3.10+ и Firefox (для `--browser`).

```powershell
cd D:\PC-game\tools\assetfinder
python -m pip install --user -r requirements.txt
python assetfinder.py sources
```

На Windows удобнее через `run.cmd`:

```powershell
.\run.cmd search "platformer" --sources kenney
```

Selenium Manager сам скачает geckodriver при первом запуске `--browser`
(нужен интернет; занимает ~10–30 секунд).

## Быстрый старт

```powershell
# поиск по нескольким каталогам
python assetfinder.py search "pixel forest" --sources kenney,opengameart --limit 5

# скачать всё найденное
python assetfinder.py search "wood" --sources ambientcg --limit 3 --download

# скачать конкретный пак
python assetfinder.py download https://kenney.nl/assets/mini-shop --out downloads

# 2K-текстура Poly Haven
python assetfinder.py download https://polyhaven.com/a/asphalt_01 --resolution 2k --format jpg

# PBR-материал ambientCG
python assetfinder.py download https://ambientcg.com/a/Wood096 --attribute 1K-JPG

# любые файлы со страницы
python assetfinder.py grab https://opengameart.org/content/forest-background --ext zip,png,gif

# JS-страница: рендер в Firefox + клик по кнопкам
python assetfinder.py grab https://example.com/downloads --browser --click ".show-files" --ext zip
```

## Команды

### `search`

```
python assetfinder.py search "ЗАПРОС" [опции]
```

| Опция | Описание |
|---|---|
| `--sources kenney,opengameart,...` | список источников (по умолчанию kenney, opengameart, polyhaven, ambientcg) |
| `--limit N` | результатов **на каждый** источник |
| `--download` | скачать найденное |
| `--out DIR` | папка загрузок (по умолчанию `downloads`) |
| `--json` | вывод в JSON (удобно для скриптов) |
| `--type ...` | Poly Haven: `textures|hdris|models|all`; ambientCG: `Material|HDRI` |
| `--resolution 1k` | Poly Haven: `1k/2k/4k/8k` |
| `--format jpg` | Poly Haven: `jpg/png/exr/hdr/gltf` |
| `--all-maps` | Poly Haven: скачать все карты (diffuse, normal, roughness…) |
| `--attribute 1K-JPG` | ambientCG: вариант архива |

### `download`

```
python assetfinder.py download URL [опции]
```

Поддерживаются страницы Kenney, OpenGameArt, Poly Haven, ambientCG и прямые
ссылки на файлы. Для незнакомого сайта команда автоматически работает как
`grab`.

| Опция | Описание |
|---|---|
| `--out DIR` | папка загрузок |
| `--resolution`, `--format`, `--all-maps`, `--attribute` | как у `search` |
| `--browser` | открыть страницу в Firefox и собрать ссылки после JS |
| `--images` | учитывать `<img>` и `srcset` |
| `--headed` | показать окно браузера |
| `--wait 4` | сколько ждать после загрузки страницы |
| `--click "sel1,sel2"` | кликнуть по элементам перед сбором ссылок |
| `--dry-run` | показать ссылки, ничего не скачивая |
| `--max-size 500` | не качать файлы больше 500 МБ |

### `grab`

```
python assetfinder.py grab URL [--ext zip,png] [--browser] [--limit 50]
```

Собирает ссылки на файлы с произвольной страницы и скачивает их в
`downloads/grab/<host>__<slug>/`. По умолчанию понимает архивы, изображения,
аудио, 3D-форматы и шрифты.

### `sources`

Показывает список источников и примеры команд.

## Cookie и закрытые страницы

Некоторые сайты (например, CraftPix) требуют вход. Передайте cookie строкой
или файлом:

```powershell
python assetfinder.py grab "https://craftpix.net/freebies/page/24/" `
  --cookie-file cookies.txt --ext zip --browser
```

`--cookie-file` понимает:
- строку `name=value; name2=value2`;
- JSON-экспорт Cookie-Editor;
- Netscape `cookies.txt`.

Cookie не пишется в манифест и не логируется.

## Selenium / geckodriver

`--browser` запускает настоящий Firefox:

- Selenium Manager (входит в `selenium>=4.6`) сам находит/скачивает geckodriver;
- по умолчанию окно скрыто (`-headless`), для отладки — `--headed`;
- `--wait` задаёт паузу после `load`, `--click` — селекторы кнопок;
- `--cookie-file` подставляется и в Firefox (best-effort; HttpOnly-cookie
  браузеру через Selenium добавить нельзя);
- после рендера ссылки собираются из DOM, а скачивание идёт обычным
  `requests` (быстрее и с прогрессом).

Если geckodriver не скачивается автоматически, положите `geckodriver.exe` в
`PATH` — Selenium найдёт его сам.

## Структура загрузок

```
downloads/
  manifest.jsonl                 # источник, лицензия, автор, файлы
  kenney/mini-shop/mini-shop.zip
  opengameart/forest-background/parallax_forest_pack.zip
  polyhaven/asphalt_01/asphalt_01_Diffuse_1k.jpg
  ambientcg/Wood096/Wood096_1K-JPG.zip
  grab/<host>__<page>/...
```

Имена файлов берутся из `Content-Disposition`, поэтому сохраняются
оригинальными; повторы получают суффикс с временем.

## Проблемы и решения

| Симптом | Что делать |
|---|---|
| `Openverse временно недоступен (HTTP 504)` | у Openverse бывают сбои; повторите позже или уберите его из `--sources` |
| `HTTP 403` / HTML вместо файла | нужна cookie или другой User-Agent; попробуйте `--cookie-file`, `--browser` |
| Ссылки не находятся | страница рендерится JS: `--browser --wait 6`, при необходимости `--click` |
| Файл слишком большой | `--max-size 200` (МБ) |
| Много лишних файлов в `grab` | ограничьте `--ext zip` и `--limit` |
| Selenium долго стартует | первый запуск скачивает geckodriver; дальше быстрее |

## Этика и лицензии

- Инструмент скачивает только то, что доступно без обхода платного доступа.
- Уважайте лицензии: CC0 можно использовать свободно, CC-BY требует указания
  автора, GPL — соблюдения условий лицензии.
- Не ставьте `--delay 0` и не запускайте массовый `grab` по чужим сайтам.
- `manifest.jsonl` хранит автора и лицензию — используйте его при атрибуции.

## Зависимости

```
requests>=2.31
beautifulsoup4>=4.12
selenium>=4.20
```
