"""
State Attorney General Press Release Monitor
Checks all 50 state AG websites for new press releases and sends an email alert.
State is stored in ag_state.json in the same directory.
Config (email credentials) is stored in ag_config.json (local) or env var (GitHub Actions).

Run with --seed to snapshot current press releases without sending email.
Run with --state AL,TX to only check specific states (comma-separated abbreviations).
"""

import json
import os
import re
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
    print("ERROR: Missing packages. Run:")
    print("  pip install requests beautifulsoup4")
    sys.exit(1)

try:
    from playwright.sync_api import sync_playwright
    PLAYWRIGHT_AVAILABLE = True
except ImportError:
    PLAYWRIGHT_AVAILABLE = False

SCRIPT_DIR = Path(__file__).parent
STATE_FILE = SCRIPT_DIR / "ag_state.json"
SOURCES_FILE = SCRIPT_DIR / "ag_sources.json"
CONFIG_FILE = SCRIPT_DIR / "ag_config.json"
LOG_FILE = SCRIPT_DIR / "ag_log.txt"

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

    # RSS 2.0
    for item in soup.find_all("item"):
        link = item.find("link")
        title = item.find("title")
        pub_date = item.find("pubDate") or item.find("pubdate")
        guid = item.find("guid")

        item_url = (link.get_text(strip=True) if link else "")
        item_id = (guid.get_text(strip=True) if guid else item_url)
        items.append({
            "id": item_id,
            "title": title.get_text(strip=True) if title else "(no title)",
            "date": pub_date.get_text(strip=True) if pub_date else "",
            "url": item_url,
        })

    # Atom
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
    """Parse HTML string into list of {id, title, date, url} press release dicts."""
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

        # Skip self-links (the page linking back to itself)
        if full_url.rstrip("/") == page_url.rstrip("/"):
            continue

        parsed_base = urlparse(base_url)
        parsed_link = urlparse(full_url)
        if parsed_link.netloc and parsed_link.netloc != parsed_base.netloc:
            continue

        # Skip links that don't match the required URL pattern (if configured)
        if item_url_pattern and not re.search(item_url_pattern, full_url):
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

        items.append({
            "id": full_url,
            "title": title,
            "date": date,
            "url": full_url,
        })

    seen = set()
    deduped = []
    for item in items:
        if item["id"] not in seen:
            seen.add(item["id"])
            deduped.append(item)

    max_items = source.get("max_items", 50)
    deduped = deduped[:max_items]

    return deduped if deduped else None


def fetch_html(source):
    """Scrape an HTML press release listing page using the source config."""
    url = source["press_url"]
    resp = fetch_url(url)
    if not resp:
        return None

    return parse_html_content(resp.text, source, url)


def fetch_html_playwright(source):
    """Fetch a press release listing page using a headless browser (for bot-blocked sites)."""
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

        # Try configured selectors first, then fall back to all links
        items = parse_html_content(html, source, url)
        if items:
            log(f"  Playwright found {len(items)} item(s) with configured selector")
            return items

        # Fallback: try with generic "a" selector to see what links are available
        fallback_source = dict(source, item_selector="a", container_selector=None)
        items = parse_html_content(html, fallback_source, url)
        if items:
            log(f"  Playwright found {len(items)} item(s) with fallback 'a' selector")
            return items

        log(f"  Playwright: page loaded but no links matched — check selectors")
        return None
    except Exception as e:
        log(f"  Playwright error for {url}: {e}")
        return None


def resolve_dynamic_url(source):
    """Return source with press_url resolved if dynamic_url template is set."""
    dynamic_url = source.get("dynamic_url")
    if not dynamic_url:
        return source
    now = datetime.now()
    resolved = dynamic_url.format(year=now.year, month=now.month)
    return {**source, "press_url": resolved}


def fetch_press_releases(source):
    """Return list of press release dicts for a state source config."""
    abbr = source["abbr"]
    source = resolve_dynamic_url(source)

    rss_url = source.get("rss_url")
    if rss_url:
        items = fetch_rss(rss_url)
        if items is not None:
            return items
        log(f"  [{abbr}] RSS fetch failed, falling back to HTML scrape")

    if source.get("use_playwright"):
        items = fetch_html_playwright(source)
        if items is not None:
            return items
        log(f"  [{abbr}] Playwright fetch failed, falling back to regular scrape")

    return fetch_html(source)


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


def load_sources(state_filter=None):
    with open(SOURCES_FILE, encoding="utf-8") as f:
        sources = json.load(f)
    if state_filter:
        abbrs = {s.strip().upper() for s in state_filter.split(",")}
        sources = [s for s in sources if s["abbr"].upper() in abbrs]
    return sources


# ---------------------------------------------------------------------------
# Email
# ---------------------------------------------------------------------------

def load_config():
    if os.environ.get("GMAIL_APP_PASSWORD"):
        return {
            "email_from": "lbaldwin08@gmail.com",
            "email_to": "lbaldwin08@gmail.com",
            "gmail_app_password": os.environ["GMAIL_APP_PASSWORD"],
        }
    with open(CONFIG_FILE, encoding="utf-8") as f:
        return json.load(f)


def send_email(new_items_by_state):
    cfg = load_config()

    total = sum(len(v) for v in new_items_by_state.values())
    states_hit = list(new_items_by_state.keys())

    if total == 1:
        only_state = states_hit[0]
        only_item = new_items_by_state[only_state][0]
        subject = f"New AG Press Release ({only_state}): {only_item['title'][:55]}"
    elif len(states_hit) == 1:
        subject = f"{total} New AG Press Releases — {states_hit[0]}"
    else:
        subject = f"{total} New AG Press Releases across {len(states_hit)} states"

    rows_text = []
    rows_html = []

    for state_name, items in sorted(new_items_by_state.items()):
        for item in items:
            rows_text.append(
                f"{state_name}  |  {item['date']}  |  {item['title']}\n"
                f"  {item['url']}\n"
            )
            date_cell = item['date'] or "&nbsp;"
            rows_html.append(
                f"<tr>"
                f"<td style='padding:4px 8px;white-space:nowrap;font-weight:bold'>{state_name}</td>"
                f"<td style='padding:4px 8px;white-space:nowrap'>{date_cell}</td>"
                f"<td style='padding:4px 8px'><a href='{item['url']}'>{item['title']}</a></td>"
                f"</tr>"
            )

    body_text = "\n".join(rows_text)
    body_html = f"""
<html><body style="font-family:Arial,sans-serif;font-size:14px">
<h2 style="color:#1a3a5c">State AG Press Releases — {total} New Item{"s" if total != 1 else ""}</h2>
<table border="1" cellspacing="0" cellpadding="0"
       style="border-collapse:collapse;border-color:#ccc;width:100%">
  <thead style="background:#1a3a5c;color:white">
    <tr>
      <th style="padding:6px 8px;text-align:left">State</th>
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

def main(seed=False, state_filter=None):
    action = "Seeding" if seed else "Checking for new"
    log(f"{action} AG press releases...")

    sources = load_sources(state_filter)
    log(f"Checking {len(sources)} state(s).")

    state = load_state()
    seen_ids = state.get("seen_ids", {})

    new_items_by_state = {}
    errors = []

    for source in sources:
        abbr = source["abbr"]
        state_name = source["state"]
        log(f"[{abbr}] Fetching {source.get('rss_url') or source['press_url']}")

        try:
            items = fetch_press_releases(source)
        except Exception as e:
            log(f"[{abbr}] ERROR: {e}")
            errors.append(abbr)
            continue

        if items is None:
            log(f"[{abbr}] No items returned (fetch failed or empty page).")
            errors.append(abbr)
            continue

        log(f"[{abbr}] Found {len(items)} item(s) on page.")

        state_seen = set(seen_ids.get(abbr, []))
        new = [item for item in items if item["id"] not in state_seen]

        if seed:
            log(f"[{abbr}] Seed mode: marking {len(items)} items as seen.")
        elif new:
            log(f"[{abbr}] {len(new)} new item(s):")
            for item in new:
                log(f"  NEW: {item['title']} | {item['date']} | {item['url']}")
            new_items_by_state[state_name] = new
        else:
            log(f"[{abbr}] No new items.")

        # Update seen IDs (cap at 500 per state to keep file size manageable)
        all_ids = list(state_seen | {item["id"] for item in items})
        seen_ids[abbr] = all_ids[-500:]

    # Persist state
    state["seen_ids"] = seen_ids
    state["last_run"] = datetime.now().isoformat()
    save_state(state)

    if errors:
        log(f"States with fetch errors: {', '.join(errors)}")

    if not seed and new_items_by_state:
        total = sum(len(v) for v in new_items_by_state.values())
        log(f"Sending email: {total} new item(s) across {len(new_items_by_state)} state(s).")
        try:
            send_email(new_items_by_state)
            log("Email sent.")
        except Exception as e:
            log(f"ERROR sending email: {e}")
    elif not seed:
        log("No new press releases found.")

    log("Done.")


if __name__ == "__main__":
    seed_mode = "--seed" in sys.argv
    state_arg = next((a.split("=", 1)[1] for a in sys.argv if a.startswith("--state=")), None)
    main(seed=seed_mode, state_filter=state_arg)
