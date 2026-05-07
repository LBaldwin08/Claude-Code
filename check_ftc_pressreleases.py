"""
FTC Press Release Monitor
Checks ftc.gov for new press releases and sends an email alert.
State is stored in ftc_state.json in the same directory.
Config (email credentials) is from FTC_GMAIL_APP_PASSWORD or GMAIL_APP_PASSWORD
env var (GitHub Actions), or ftc_config.json (local).

Run with --seed to snapshot current press releases without sending email.
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
from urllib.parse import urljoin

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
STATE_FILE = SCRIPT_DIR / "ftc_state.json"
CONFIG_FILE = SCRIPT_DIR / "ftc_config.json"
LOG_FILE = SCRIPT_DIR / "ftc_log.txt"

FTC_URL = "https://www.ftc.gov/news-events/news/press-releases"
FTC_BASE = "https://www.ftc.gov"
PRESS_RELEASE_PATTERN = re.compile(r"/news-events/news/press-releases/\d{4}/\d{2}/\S+")

HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
        "AppleWebKit/537.36 (KHTML, like Gecko) "
        "Chrome/124.0 Safari/537.36"
    )
}


def log(msg):
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    line = f"[{timestamp}] {msg}"
    print(line)
    with open(LOG_FILE, "a", encoding="utf-8") as f:
        f.write(line + "\n")


def parse_releases(html):
    """Extract press release items from rendered HTML."""
    soup = BeautifulSoup(html, "html.parser")
    items = []
    seen_urls = set()

    for link in soup.find_all("a", href=True):
        href = link["href"]
        if not PRESS_RELEASE_PATTERN.search(href):
            continue

        full_url = href if href.startswith("http") else urljoin(FTC_BASE, href)
        # Normalize: strip query strings and fragments
        full_url = full_url.split("?")[0].split("#")[0].rstrip("/")

        if full_url in seen_urls:
            continue
        seen_urls.add(full_url)

        title = link.get_text(strip=True)
        if not title or len(title) < 5:
            continue

        # Look for a date in the nearest ancestor container
        date = ""
        parent = link.find_parent(["li", "article", "div", "tr"])
        if parent:
            time_tag = parent.find("time")
            if time_tag:
                date = time_tag.get("datetime", "") or time_tag.get_text(strip=True)
            if not date:
                date_tag = parent.find(class_=lambda c: c and any(
                    kw in c.lower() for kw in ["date", "time", "posted"]
                ))
                if date_tag:
                    date = date_tag.get_text(strip=True)

        items.append({"id": full_url, "title": title, "date": date, "url": full_url})

    return items


def fetch_with_playwright():
    if not PLAYWRIGHT_AVAILABLE:
        log("ERROR: Playwright not installed. Run: pip install playwright && playwright install chromium")
        return None

    log(f"Using Playwright to fetch {FTC_URL}")
    try:
        with sync_playwright() as p:
            browser = p.chromium.launch(headless=True)
            page = browser.new_page()
            page.set_extra_http_headers({"User-Agent": HEADERS["User-Agent"]})
            page.goto(FTC_URL, timeout=45000, wait_until="domcontentloaded")
            # Wait for press release links to appear in the DOM
            try:
                page.wait_for_selector("a[href*='/press-releases/']", timeout=10000)
            except Exception:
                pass
            page.wait_for_timeout(2000)
            html = page.content()
            browser.close()

        items = parse_releases(html)
        log(f"Playwright found {len(items)} press release link(s).")
        return items if items else None
    except Exception as e:
        log(f"Playwright error: {e}")
        return None


def fetch_with_requests():
    """Fallback plain HTTP fetch — may return 403 on FTC."""
    for attempt in range(1, 4):
        try:
            resp = requests.get(FTC_URL, headers=HEADERS, timeout=(15, 60))
            resp.raise_for_status()
            items = parse_releases(resp.text)
            log(f"requests found {len(items)} press release link(s).")
            return items if items else None
        except Exception as e:
            log(f"Attempt {attempt}/3 failed: {e}")
            if attempt < 3:
                time.sleep(20)
    return None


def fetch_press_releases():
    items = fetch_with_playwright()
    if items is not None:
        return items
    log("Playwright failed or unavailable; trying plain HTTP as fallback.")
    return fetch_with_requests()


# ---------------------------------------------------------------------------
# State persistence
# ---------------------------------------------------------------------------

def load_state():
    if STATE_FILE.exists():
        with open(STATE_FILE, encoding="utf-8") as f:
            return json.load(f)
    return {"seen_ids": [], "last_run": None}


def save_state(state):
    with open(STATE_FILE, "w", encoding="utf-8") as f:
        json.dump(state, f, indent=2)


# ---------------------------------------------------------------------------
# Email
# ---------------------------------------------------------------------------

def load_config():
    pw = os.environ.get("FTC_GMAIL_APP_PASSWORD") or os.environ.get("GMAIL_APP_PASSWORD")
    if pw:
        return {
            "email_from": "lbaldwin08@gmail.com",
            "email_to": "lbaldwin08@gmail.com",
            "gmail_app_password": pw,
        }
    with open(CONFIG_FILE, encoding="utf-8") as f:
        return json.load(f)


def send_email(new_items):
    cfg = load_config()
    count = len(new_items)

    if count == 1:
        subject = f"New FTC Press Release: {new_items[0]['title'][:60]}"
    else:
        subject = f"{count} New FTC Press Releases"

    rows_text = []
    rows_html = []
    for item in new_items:
        rows_text.append(
            f"{item['date']}  |  {item['title']}\n"
            f"  {item['url']}\n"
        )
        date_cell = item["date"] or "&nbsp;"
        rows_html.append(
            f"<tr>"
            f"<td style='padding:4px 8px;white-space:nowrap'>{date_cell}</td>"
            f"<td style='padding:4px 8px'><a href='{item['url']}'>{item['title']}</a></td>"
            f"</tr>"
        )

    body_text = "\n".join(rows_text) + f"\n\nView all: {FTC_URL}"
    body_html = f"""
<html><body style="font-family:Arial,sans-serif;font-size:14px">
<h2 style="color:#1a3a5c">FTC — New Press Release{"s" if count > 1 else ""}</h2>
<table border="1" cellspacing="0" cellpadding="0"
       style="border-collapse:collapse;border-color:#ccc;width:100%">
  <thead style="background:#1a3a5c;color:white">
    <tr>
      <th style="padding:6px 8px;text-align:left">Date</th>
      <th style="padding:6px 8px;text-align:left">Title</th>
    </tr>
  </thead>
  <tbody>
    {"".join(rows_html)}
  </tbody>
</table>
<p style="margin-top:16px">
  <a href="{FTC_URL}">View all FTC press releases</a>
</p>
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
    log(f"{action} FTC press releases...")

    try:
        items = fetch_press_releases()
    except Exception as e:
        log(f"ERROR fetching press releases: {e}")
        log("Skipping this run — will retry next scheduled check.")
        sys.exit(0)

    if items is None:
        log("No items returned (fetch failed or empty page). Skipping.")
        sys.exit(0)

    log(f"Found {len(items)} press release(s) on page.")

    state = load_state()
    seen_ids = set(state["seen_ids"])

    new_items = [item for item in items if item["id"] not in seen_ids]

    if seed:
        log(f"Seed mode: marking {len(items)} press release(s) as seen (no email sent).")
    elif not new_items:
        log("No new press releases.")
    else:
        log(f"{len(new_items)} new press release(s)!")
        for item in new_items:
            log(f"  NEW: [{item['date']}] {item['title']}")
            log(f"       {item['url']}")
        try:
            send_email(new_items)
            log("Email notification sent.")
        except Exception as e:
            log(f"ERROR sending email: {e}")

    # Cap stored IDs at 500 to keep the state file manageable
    all_ids = list(seen_ids | {item["id"] for item in items})
    state["seen_ids"] = all_ids[-500:]
    state["last_run"] = datetime.now().isoformat()
    save_state(state)

    log("Done.")


if __name__ == "__main__":
    main(seed="--seed" in sys.argv)
