"""
Cyclospora / Taylor Farms / Taco Bell Alert Monitor
Checks FDA and CDC outbreak, recall, and newsroom pages for new items and,
for any item whose title mentions "cyclospora" (or that comes from a page
that is cyclospora-specific), fetches the linked page and looks for a
mention of "Taylor Farms" or "Taco Bell". Sends an email alert on a match.

Sources are configured in cyclospora_sources.json.
State is stored in cyclospora_state.json in the same directory.
Config (email credentials) is from CYCLOSPORA_GMAIL_APP_PASSWORD or
GMAIL_APP_PASSWORD env var (GitHub Actions), or cyclospora_config.json (local).

Run with --seed to snapshot current items without checking/alerting.
"""

import json
import os
import smtplib
import sys
import time
from datetime import datetime
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from pathlib import Path
from urllib.parse import urljoin, urlparse

try:
    import requests
    from bs4 import BeautifulSoup
except ImportError:
    print("ERROR: Missing packages. Run: pip install requests beautifulsoup4")
    sys.exit(1)

try:
    from playwright.sync_api import sync_playwright
    PLAYWRIGHT_AVAILABLE = True
except ImportError:
    PLAYWRIGHT_AVAILABLE = False

SCRIPT_DIR = Path(__file__).parent
STATE_FILE = SCRIPT_DIR / "cyclospora_state.json"
SOURCES_FILE = SCRIPT_DIR / "cyclospora_sources.json"
CONFIG_FILE = SCRIPT_DIR / "cyclospora_config.json"
LOG_FILE = SCRIPT_DIR / "cyclospora_log.txt"

COMPANY_KEYWORDS = ["taylor farms", "taco bell"]

HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
        "AppleWebKit/537.36 (KHTML, like Gecko) "
        "Chrome/124.0 Safari/537.36"
    )
}

SESSION = requests.Session()
SESSION.headers.update(HEADERS)


def log(msg):
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    line = f"[{timestamp}] {msg}"
    print(line)
    with open(LOG_FILE, "a", encoding="utf-8") as f:
        f.write(line + "\n")


# ---------------------------------------------------------------------------
# Fetching
# ---------------------------------------------------------------------------

def fetch_url(url, timeout=(15, 60), retries=3, delay=20):
    for attempt in range(1, retries + 1):
        try:
            resp = SESSION.get(url, timeout=timeout, allow_redirects=True)
            resp.raise_for_status()
            return resp
        except Exception as e:
            log(f"  Attempt {attempt}/{retries} failed for {url}: {e}")
            if attempt < retries:
                time.sleep(delay)
    return None


def fetch_rss(url):
    """Parse an RSS/Atom feed and return list of {id, title, date, url}."""
    resp = fetch_url(url)
    if not resp:
        return None

    soup = BeautifulSoup(resp.content, "xml")
    items = []

    for item in soup.find_all("item"):
        link = item.find("link")
        title = item.find("title")
        pub_date = item.find("pubDate") or item.find("pubdate")
        guid = item.find("guid")

        item_url = link.get_text(strip=True) if link else ""
        item_id = guid.get_text(strip=True) if guid else item_url
        items.append({
            "id": item_id,
            "title": title.get_text(strip=True) if title else "(no title)",
            "date": pub_date.get_text(strip=True) if pub_date else "",
            "url": item_url,
        })

    if not items:
        for entry in soup.find_all("entry"):
            link = entry.find("link")
            title = entry.find("title")
            updated = entry.find("updated") or entry.find("published")
            entry_id = entry.find("id")

            entry_url = link.get("href", "") if link else ""
            unique_id = entry_id.get_text(strip=True) if entry_id else entry_url
            items.append({
                "id": unique_id,
                "title": title.get_text(strip=True) if title else "(no title)",
                "date": updated.get_text(strip=True) if updated else "",
                "url": entry_url,
            })

    return items if items else None


def parse_html_content(html, source, page_url):
    """Parse HTML string into list of {id, title, date, url} items."""
    soup = BeautifulSoup(html, "html.parser")
    items = []

    container_sel = source.get("container_selector")
    item_sel = source.get("item_selector", "a")
    base_url = source.get("base_url", page_url)

    container = soup
    if container_sel:
        container = soup.select_one(container_sel) or soup

    links = container.select(item_sel) if item_sel else container.find_all("a")
    item_url_pattern = source.get("item_url_pattern")

    for link in links:
        href = link.get("href", "")
        if not href or href.startswith("#") or href.startswith("mailto:") or href.startswith("tel:") or href.startswith("javascript:"):
            continue

        full_url = href if href.startswith("http") else urljoin(base_url, href)
        full_url = full_url.split("#")[0].rstrip("/")

        if full_url.rstrip("/") == page_url.rstrip("/"):
            continue

        parsed_base = urlparse(base_url)
        parsed_link = urlparse(full_url)
        if parsed_link.netloc and parsed_link.netloc != parsed_base.netloc:
            continue

        if item_url_pattern:
            import re
            if not re.search(item_url_pattern, full_url):
                continue

        title = link.get_text(strip=True)
        if not title or len(title) < 5:
            continue

        parent = link.find_parent(["li", "tr", "div", "article"])
        date = ""
        if parent:
            date_tag = parent.find(class_=lambda c: c and any(
                kw in c.lower() for kw in ["date", "time", "posted"]
            ))
            if not date_tag:
                date_tag = parent.find("time")
            if date_tag:
                date = date_tag.get("datetime", "") or date_tag.get_text(strip=True)

        items.append({"id": full_url, "title": title, "date": date, "url": full_url})

    seen = set()
    deduped = []
    for item in items:
        if item["id"] not in seen:
            seen.add(item["id"])
            deduped.append(item)

    return deduped if deduped else None


def fetch_html(source):
    url = source["press_url"]
    resp = fetch_url(url)
    if not resp:
        return None
    return parse_html_content(resp.text, source, url)


def fetch_html_playwright(source):
    if not PLAYWRIGHT_AVAILABLE:
        log("  Playwright not installed. Run: pip install playwright && playwright install chromium")
        return None

    url = source["press_url"]
    log(f"  Using Playwright headless browser for {url}")
    try:
        with sync_playwright() as p:
            browser = p.chromium.launch(headless=True)
            page = browser.new_page()
            page.set_extra_http_headers({"User-Agent": HEADERS["User-Agent"]})
            page.goto(url, timeout=30000, wait_until="domcontentloaded")
            page.wait_for_timeout(2000)
            html = page.content()
            title = page.title()
            browser.close()

        log(f"  Playwright loaded page: '{title}' ({len(html)} chars)")

        items = parse_html_content(html, source, url)
        if items:
            log(f"  Playwright found {len(items)} item(s) with configured selector")
            return items

        fallback_source = dict(source, item_selector="a", container_selector=None)
        items = parse_html_content(html, fallback_source, url)
        if items:
            log(f"  Playwright found {len(items)} item(s) with fallback 'a' selector")
            return items

        log("  Playwright: page loaded but no links matched — check selectors")
        return None
    except Exception as e:
        log(f"  Playwright error for {url}: {e}")
        return None


def fetch_listing(source):
    """Return list of {id, title, date, url} dicts for a configured source."""
    sid = source["id"]

    rss_url = source.get("rss_url")
    if rss_url:
        items = fetch_rss(rss_url)
        if items is not None:
            return items
        log(f"  [{sid}] RSS fetch failed, falling back to HTML scrape")

    if source.get("use_playwright"):
        items = fetch_html_playwright(source)
        if items is not None:
            return items
        log(f"  [{sid}] Playwright fetch failed, falling back to plain HTTP")

    return fetch_html(source)


def fetch_detail_text(url):
    """Fetch a single item's page and return its visible text (best effort)."""
    if PLAYWRIGHT_AVAILABLE:
        try:
            with sync_playwright() as p:
                browser = p.chromium.launch(headless=True)
                page = browser.new_page()
                page.set_extra_http_headers({"User-Agent": HEADERS["User-Agent"]})
                page.goto(url, timeout=30000, wait_until="domcontentloaded")
                page.wait_for_timeout(1500)
                text = page.inner_text("body")
                browser.close()
            if text:
                return text
        except Exception as e:
            log(f"    Playwright detail fetch failed for {url}: {e}")

    resp = fetch_url(url, retries=2, delay=10)
    if resp:
        soup = BeautifulSoup(resp.text, "html.parser")
        return soup.get_text(" ", strip=True)
    return ""


# ---------------------------------------------------------------------------
# State persistence
# ---------------------------------------------------------------------------

def load_state():
    if STATE_FILE.exists():
        with open(STATE_FILE, encoding="utf-8") as f:
            return json.load(f)
    return {"seen_ids": {}, "last_run": None}


def save_state(state):
    with open(STATE_FILE, "w", encoding="utf-8") as f:
        json.dump(state, f, indent=2)


def load_sources():
    with open(SOURCES_FILE, encoding="utf-8") as f:
        return json.load(f)


# ---------------------------------------------------------------------------
# Email
# ---------------------------------------------------------------------------

def load_config():
    pw = os.environ.get("CYCLOSPORA_GMAIL_APP_PASSWORD") or os.environ.get("GMAIL_APP_PASSWORD")
    if pw:
        return {
            "email_from": "lbaldwin08@gmail.com",
            "email_to": "lbaldwin08@gmail.com",
            "gmail_app_password": pw,
        }
    with open(CONFIG_FILE, encoding="utf-8") as f:
        return json.load(f)


def send_email(matches):
    cfg = load_config()
    count = len(matches)

    if count == 1:
        subject = f"Cyclospora Alert ({matches[0]['company']}): {matches[0]['title'][:55]}"
    else:
        subject = f"{count} New Cyclospora Alerts (Taylor Farms / Taco Bell)"

    rows_text = []
    rows_html = []
    for item in matches:
        rows_text.append(
            f"{item['source']}  |  {item['company']}  |  {item['date']}  |  {item['title']}\n"
            f"  {item['url']}\n"
        )
        date_cell = item["date"] or "&nbsp;"
        rows_html.append(
            f"<tr>"
            f"<td style='padding:4px 8px;white-space:nowrap'>{item['source']}</td>"
            f"<td style='padding:4px 8px;white-space:nowrap;font-weight:bold'>{item['company']}</td>"
            f"<td style='padding:4px 8px;white-space:nowrap'>{date_cell}</td>"
            f"<td style='padding:4px 8px'><a href='{item['url']}'>{item['title']}</a></td>"
            f"</tr>"
        )

    body_text = "\n".join(rows_text)
    body_html = f"""
<html><body style="font-family:Arial,sans-serif;font-size:14px">
<h2 style="color:#8b1a1a">Cyclospora Alert — {count} New Match{"es" if count != 1 else ""}</h2>
<table border="1" cellspacing="0" cellpadding="0"
       style="border-collapse:collapse;border-color:#ccc;width:100%">
  <thead style="background:#8b1a1a;color:white">
    <tr>
      <th style="padding:6px 8px;text-align:left">Source</th>
      <th style="padding:6px 8px;text-align:left">Company</th>
      <th style="padding:6px 8px;text-align:left">Date</th>
      <th style="padding:6px 8px;text-align:left">Title</th>
    </tr>
  </thead>
  <tbody>
    {"".join(rows_html)}
  </tbody>
</table>
</body></html>
"""

    msg = MIMEMultipart("alternative")
    msg["Subject"] = subject
    msg["From"] = cfg["email_from"]
    msg["To"] = cfg["email_to"]
    msg.attach(MIMEText(body_text, "plain"))
    msg.attach(MIMEText(body_html, "html"))

    with smtplib.SMTP_SSL("smtp.gmail.com", 465) as server:
        server.login(cfg["email_from"], cfg["gmail_app_password"])
        server.sendmail(cfg["email_from"], cfg["email_to"], msg.as_string())


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main(seed=False):
    action = "Seeding" if seed else "Checking for new"
    log(f"{action} FDA/CDC cyclospora items...")

    sources = load_sources()
    state = load_state()
    seen_ids = state.get("seen_ids", {})

    matches = []

    for source in sources:
        sid = source["id"]
        log(f"[{sid}] Fetching {source.get('rss_url') or source['press_url']}")

        try:
            items = fetch_listing(source)
        except Exception as e:
            log(f"[{sid}] ERROR: {e}")
            continue

        if items is None:
            log(f"[{sid}] No items returned (fetch failed or empty page).")
            continue

        log(f"[{sid}] Found {len(items)} item(s) on page.")

        source_seen = set(seen_ids.get(sid, []))
        new_items = [it for it in items if it["id"] not in source_seen]

        if seed:
            log(f"[{sid}] Seed mode: marking {len(items)} item(s) as seen (no checks/alerts).")
        elif new_items:
            log(f"[{sid}] {len(new_items)} new item(s) to evaluate.")
            for item in new_items:
                title_lower = item["title"].lower()
                is_candidate = source.get("cyclospora_only") or "cyclospora" in title_lower
                if not is_candidate:
                    continue

                log(f"[{sid}] Candidate: {item['title']}")
                try:
                    detail_text = fetch_detail_text(item["url"])
                except Exception as e:
                    log(f"[{sid}] Detail fetch error for {item['url']}: {e}")
                    detail_text = ""

                combined = f"{item['title']} {detail_text}".lower()
                hit = next((kw for kw in COMPANY_KEYWORDS if kw in combined), None)
                if hit:
                    company = hit.title()
                    log(f"[{sid}] MATCH ({company}): {item['title']} -> {item['url']}")
                    matches.append({**item, "source": source["name"], "company": company})
                else:
                    log(f"[{sid}] No Taylor Farms / Taco Bell mention found.")
        else:
            log(f"[{sid}] No new items.")

        all_ids = list(source_seen | {it["id"] for it in items})
        seen_ids[sid] = all_ids[-500:]

    state["seen_ids"] = seen_ids
    state["last_run"] = datetime.now().isoformat()
    save_state(state)

    if not seed and matches:
        log(f"Sending alert email: {len(matches)} match(es).")
        try:
            send_email(matches)
            log("Email sent.")
        except Exception as e:
            log(f"ERROR sending email: {e}")
    elif not seed:
        log("No new cyclospora + Taylor Farms/Taco Bell matches.")

    log("Done.")


if __name__ == "__main__":
    main(seed="--seed" in sys.argv)
