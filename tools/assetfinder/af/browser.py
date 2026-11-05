"""Selenium/geckodriver — рендер JS-страниц и сбор ссылок."""

from __future__ import annotations

import time


def render(
    url: str,
    wait: float = 4.0,
    headless: bool = True,
    click: list[str] | None = None,
    cookies: dict[str, str] | None = None,
) -> tuple[str, list[str]]:
    """Открывает страницу в Firefox, возвращает (html, ссылки).

    Selenium Manager сам скачает geckodriver при первом запуске.
    cookies добавляются для текущего домена (best-effort, не HttpOnly).
    """
    try:
        from selenium import webdriver
        from selenium.webdriver.firefox.options import Options
    except ImportError as exc:
        raise RuntimeError(
            "Для --browser установите selenium: python -m pip install selenium"
        ) from exc

    options = Options()
    if headless:
        options.add_argument("-headless")
    options.set_preference("dom.webdriver.enabled", False)
    options.set_preference("useAutomationExtension", False)

    driver = webdriver.Firefox(options=options)
    try:
        driver.set_page_load_timeout(90)
        driver.get(url)
        if cookies:
            added = 0
            for name, value in cookies.items():
                try:
                    driver.add_cookie({"name": name, "value": value, "path": "/"})
                    added += 1
                except Exception:
                    pass
            if added:
                driver.refresh()
        time.sleep(wait)
        for selector in click or []:
            try:
                elements = driver.find_elements("css selector", selector)
            except Exception:
                elements = []
            for element in elements:
                try:
                    driver.execute_script("arguments[0].scrollIntoView({block:'center'});", element)
                    time.sleep(0.2)
                    element.click()
                except Exception:
                    pass
            time.sleep(1.5)
        html = driver.page_source
        links = [
            href
            for href in (
                el.get_attribute("href")
                for el in driver.find_elements("tag name", "a")
            )
            if href
        ]
    finally:
        driver.quit()
    return html, links
