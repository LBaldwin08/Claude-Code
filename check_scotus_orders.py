"""
Supreme Court Orders Monitor
Checks supremecourt.gov for new orders and sends an email alert.
State is stored in scotus_orders_state.json in the same directory.
Config (email credentials) is from SCOTUS_GMAIL_APP_PASSWORD or GMAIL_APP_PASSWORD
env var (GitHub Actions), or scotus_orders_config.json (local).

Run with --seed to snapshot current orders without sending email.
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
STATE_FILE = SCRIPT_DIR / "scotus_orders_state.json"
CONFIG_FILE = SCRIPT_DIR / "scotus_orders_config.json"
LOG_FILE = SCRIPT_DIR / "scotus_orders_log.txt"

SCOTUS_BASE = "https://www.supremecourt.gov"
ORDERS_INDEX_URL = "https://www.supremecourt.gov/orders/ordersofthecourt/"
TERM_PAGE_PATTERN = re.compile(r"/orders/ordersofthecourt/(\d+)/?$")
ORDER_PDF_PATTERN = re.compile(r"/orders/courtorders/[^\s\"']+\.pdf", re.IGNORECASE)

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


def parse_filename_date(filename):
    """Parse a date from SCOTUS PDF filename format MMDDYY."""
    m = re.match(r"(\d{2})(\d{2})(\d{2})", filename)
    if m:
        mm, dd, yy = m.groups()
        try:
            return f"20{yy}-{mm}-{dd}"
        except Exception:
            pass
    return ""


def parse_orders(html):
    """Extract order PDF items from rendered HTML."""
    soup = BeautifulSoup(html, "html.parser")
    items = []
    seen_urls = set()

    for link in soup.find_all("a", href=True):
        href = link["href"]
        if not ORDER_PDF_PATTERN.search(href):
            continue

        full_url = href if href.startswith("http") else urljoin(SCOTUS_BASE, href)
        full_url = full_url.split("?")[0].split("#")[0]

        if full_url in seen_urls:
            continue
        seen_urls.add(full_url)

        title = link.get_text(strip=True)
        filename = full_url.rsplit("/", 1)[-1]
        if not title or len(title) < 3:
            title = filename

        date_str = ""
        parent = link.find_parent(["li", "tr", "div", "p", "td"])
        if parent:
            time_tag = parent.find("time")
            if time_tag:
                date_str = time_tag.get("datetime", "") or time_tag.get_text(strip=True)
            if not date_str:
                date_tag = parent.find(class_=lambda c: c and any(
                    kw in c.lower() for kw in ["date", "time", "posted"]
                ))
                if date_tag:
                    date_str = date_tag.get_text(strip=True)
        if not date_str:
            date_str = parse_filename_date(filename)

        items.append({"id": full_url, "title": title, "date": date_str, "url": full_url})

    return items


def find_current_term_url(html):
    """Find the URL for the most recent term from the orders index page."""
    soup = BeautifulSoup(html, "html.parser")
    term_links = []
    for link in soup.find_all("a", href=True):
        m = TERM_PAGE_PATTERN.search(link["href"])
        if m:
            term_num = int(m.group(1))
            href = link["href"]
            full_url = href if href.startswith("http") else urljoin(SCOTUS_BASE, href)
            term_links.append((term_num, full_url))
    if not term_links:
        return None
    term_links.sort(key=lambda x: x[0], reverse=True)
    return term_links[0][1]


def compute_fallback_term_url():
    """Compute the current SCOTUS term URL based on the calendar date.

    The October Term starts in October; before October we're still in the
    prior term (e.g. in September 2026 the term is OT25 → suffix '25').
    """
    now = datetime.now()
    year_2d = now.year % 100
    if now.month < 10:
        year_2d -= 1
    return f"{SCOTUS_BASE}/orders/ordersofthecourt/{year_2d:02d}"


def fetch_with_playwright():
    if not PLAYWRIGHT_AVAILABLE:
        log("ERROR: Playwright not installed. Run: pip install playwright && playwright install chromium")
        return None

    log(f"Using Playwright to fetch {ORDERS_INDEX_URL}")
    try:
        with sync_playwright() as p:
            browser = p.chromium.launch(headless=True)
            page = browser.new_page()
            page.set_extra_http_headers({"User-Agent": HEADERS["User-Agent"]})

            page.goto(ORDERS_INDEX_URL, timeout=45000, wait_until="domcontentloaded")
            page.wait_for_timeout(2000)
            index_html = page.content()

            term_url = find_current_term_url(index_html)
            if not term_url:
                term_url = compute_fallback_term_url()
                log(f"Could not detect term URL from index; using computed: {term_url}")
            else:
                log(f"Found current term page: {term_url}")

            page.goto(term_url, timeout=45000, wait_until="domcontentloaded")
            try:
                page.wait_for_selector("a[href*='/orders/courtorders/']", timeout=10000)
            except Exception:
                pass
            page.wait_for_timeout(2000)
            term_html = page.content()
            browser.close()

        items = parse_orders(term_html)
        log(f"Playwright found {len(items)} order(s).")
        return items if items else None
    except Exception as e:
        log(f"Playwright error: {e}")
        return None


def fetch_with_requests():
    """Fallback plain HTTP fetch — likely to 403 on supremecourt.gov."""
    for attempt in range(1, 4):
        try:
            resp = requests.get(ORDERS_INDEX_URL, headers=HEADERS, timeout=(15, 60))
            resp.raise_for_status()
            term_url = find_current_term_url(resp.text) or compute_fallback_term_url()
            resp2 = requests.get(term_url, headers=HEADERS, timeout=(15, 60))
            resp2.raise_for_status()
            items = parse_orders(resp2.text)
            log(f"requests found {len(items)} order(s).")
            return items if items else None
        except Exception as e:
            log(f"Attempt {attempt}/3 failed: {e}")
            if attempt < 3:
                time.sleep(20)
    return None


def fetch_orders():
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
    pw = (
        os.environ.get("SCOTUS_GMAIL_APP_PASSWORD")
        or os.environ.get("GMAIL_APP_PASSWORD")
    )
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
        subject = f"New SCOTUS Order: {new_items[0]['title'][:60]}"
    else:
        subject = f"{count} New Supreme Court Orders"

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

    body_text = "\n".join(rows_text) + f"\n\nView all: {ORDERS_INDEX_URL}"
    body_html = f"""
<html><body style="font-family:Arial,sans-serif;font-size:14px">
<h2 style="color:#1a3a5c">Supreme Court &#8212; New Order{"s" if count > 1 else ""}</h2>
<table border="1" cellspacing="0" cellpadding="0"
       style="border-collapse:collapse;border-color:#ccc;width:100%">
  <thead style="background:#1a3a5c;color:white">
    <tr>
      <th style="padding:6px 8px;text-align:left">Date</th>
      <th style="padding:6px 8px;text-align:left">Order</th>
    </tr>
  </thead>
  <tbody>
    {"".join(rows_html)}
  </tbody>
</table>
<p style="margin-top:16px">
  <a href="{ORDERS_INDEX_URL}">View all Supreme Court orders</a>
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
    log(f"{action} Supreme Court orders...")

    try:
        items = fetch_orders()
    except Exception as e:
        log(f"ERROR fetching orders: {e}")
        log("Skipping this run — will retry next scheduled check.")
        sys.exit(0)

    if items is None:
        log("No items returned (fetch failed or empty page). Skipping.")
        sys.exit(0)

    log(f"Found {len(items)} order(s) on page.")

    state = load_state()
    seen_ids = set(state["seen_ids"])

    new_items = [item for item in items if item["id"] not in seen_ids]

    if seed:
        log(f"Seed mode: marking {len(items)} order(s) as seen (no email sent).")
    elif not new_items:
        log("No new orders.")
    else:
        log(f"{len(new_items)} new order(s)!")
        for item in new_items:
            log(f"  NEW: [{item['date']}] {item['title']}")
            log(f"       {item['url']}")
        try:
            send_email(new_items)
            log("Email notification sent.")
        except Exception as e:
            log(f"ERROR sending email: {e}")

    all_ids = list(seen_ids | {item["id"] for item in items})
    state["seen_ids"] = all_ids[-500:]
    state["last_run"] = datetime.now().isoformat()
    save_state(state)

    log("Done.")


if __name__ == "__main__":
    main(seed="--seed" in sys.argv)
