"""
DE Court of Chancery Opinion Monitor
Checks for new opinions and sends an email alert.
State is stored in chancery_state.json in the same directory.
Config (email credentials) is stored in chancery_config.json.
"""

import json
import os
import smtplib
import sys
from datetime import datetime
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from pathlib import Path

try:
    import requests
    from bs4 import BeautifulSoup
except ImportError:
    print("ERROR: Missing packages. Run:")
    print(r"  C:\Users\lbald\AppData\Local\Python\pythoncore-3.14-64\python.exe -m pip install requests beautifulsoup4")
    sys.exit(1)

SCRIPT_DIR = Path(__file__).parent
STATE_FILE = SCRIPT_DIR / "chancery_state.json"
CONFIG_FILE = SCRIPT_DIR / "chancery_config.json"
LOG_FILE = SCRIPT_DIR / "chancery_log.txt"
URL = "https://courts.delaware.gov/opinions/List.aspx?ag=Court+of+Chancery"
OPINION_BASE = "https://courts.delaware.gov/opinions/"

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


def fetch_opinions():
    resp = requests.get(URL, headers=HEADERS, timeout=30)
    resp.raise_for_status()
    soup = BeautifulSoup(resp.text, "html.parser")

    opinions = []
    for link in soup.find_all("a", href=True):
        href = link["href"]
        if "Download.aspx?id=" in href:
            opinion_id = href.split("id=")[1].split("&")[0]
            row = link.find_parent("tr")
            cells = row.find_all("td") if row else []

            # Extract fields from table cells
            title = link.get_text(strip=True)
            date = cells[1].get_text(strip=True) if len(cells) > 1 else ""
            case_num = cells[2].get_text(strip=True) if len(cells) > 2 else ""
            judge = cells[5].get_text(strip=True) if len(cells) > 5 else ""
            description = cells[6].get_text(strip=True) if len(cells) > 6 else ""

            opinions.append({
                "id": opinion_id,
                "title": title,
                "date": date,
                "case_num": case_num,
                "judge": judge,
                "description": description,
                "url": OPINION_BASE + href.lstrip("/"),
            })

    return opinions


def load_state():
    if STATE_FILE.exists():
        with open(STATE_FILE, encoding="utf-8") as f:
            return json.load(f)
    return {"seen_ids": [], "last_run": None}


def save_state(state):
    with open(STATE_FILE, "w", encoding="utf-8") as f:
        json.dump(state, f, indent=2)


def load_config():
    # GitHub Actions: credentials come from environment variables
    if os.environ.get("GMAIL_APP_PASSWORD"):
        return {
            "email_from": "lbaldwin08@gmail.com",
            "email_to": "lbaldwin08@gmail.com",
            "gmail_app_password": os.environ["GMAIL_APP_PASSWORD"],
        }
    # Local: credentials come from config file
    with open(CONFIG_FILE, encoding="utf-8") as f:
        return json.load(f)


def send_email(new_opinions):
    cfg = load_config()
    count = len(new_opinions)
    subject = (
        f"New DE Chancery Opinion: {new_opinions[0]['title'][:60]}"
        if count == 1
        else f"{count} New DE Chancery Opinions"
    )

    # Build plain-text and HTML bodies
    rows_text = []
    rows_html = []
    for op in new_opinions:
        rows_text.append(
            f"{op['date']}  |  {op['title']}\n"
            f"  {op['case_num']}  •  {op['judge']}\n"
            f"  {op['url']}\n"
        )
        rows_html.append(
            f"<tr>"
            f"<td style='padding:4px 8px;white-space:nowrap'>{op['date']}</td>"
            f"<td style='padding:4px 8px'><a href='{op['url']}'>{op['title']}</a></td>"
            f"<td style='padding:4px 8px;white-space:nowrap'>{op['case_num']}</td>"
            f"<td style='padding:4px 8px'>{op['judge']}</td>"
            f"</tr>"
        )

    body_text = "\n".join(rows_text) + f"\n\nView all: {URL}"
    body_html = f"""
<html><body style="font-family:Arial,sans-serif;font-size:14px">
<h2 style="color:#1a3a5c">DE Court of Chancery — New Opinion{"s" if count > 1 else ""}</h2>
<table border="1" cellspacing="0" cellpadding="0" style="border-collapse:collapse;border-color:#ccc">
  <thead style="background:#1a3a5c;color:white">
    <tr>
      <th style="padding:6px 8px">Date</th>
      <th style="padding:6px 8px">Parties</th>
      <th style="padding:6px 8px">Case No.</th>
      <th style="padding:6px 8px">Judge</th>
    </tr>
  </thead>
  <tbody>
    {"".join(rows_html)}
  </tbody>
</table>
<p style="margin-top:16px">
  <a href="{URL}">View full opinions list</a>
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


def main():
    log("Checking for new DE Chancery opinions...")

    try:
        opinions = fetch_opinions()
    except Exception as e:
        log(f"ERROR fetching page: {e}")
        sys.exit(1)

    log(f"Found {len(opinions)} opinions on page.")

    state = load_state()
    seen_ids = set(state["seen_ids"])

    new_opinions = [op for op in opinions if op["id"] not in seen_ids]

    if not new_opinions:
        log("No new opinions.")
    else:
        log(f"{len(new_opinions)} new opinion(s)!")
        for op in new_opinions:
            log(f"  NEW: [{op['date']}] {op['title']} | {op['case_num']} | {op['judge']}")
            log(f"       {op['url']}")

        try:
            send_email(new_opinions)
            log("Email notification sent.")
        except Exception as e:
            log(f"ERROR sending email: {e}")

        # Update state
        seen_ids.update(op["id"] for op in new_opinions)

    state["seen_ids"] = list(seen_ids)
    state["last_run"] = datetime.now().isoformat()
    save_state(state)

    log("Done.")


if __name__ == "__main__":
    main()
