#!/usr/bin/env python3
"""
Law Firm Library & Research Job Newsletter
Runs weekly via GitHub Actions — emails results to lbaldwin08@gmail.com
"""

import os
import re
import json
import smtplib
import urllib.parse
from datetime import datetime, timezone
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from html import escape
from xml.etree import ElementTree as ET

import requests

# ── Configuration ─────────────────────────────────────────────────────────────

GMAIL_ADDRESS     = os.environ["GMAIL_ADDRESS"]
GMAIL_APP_PASSWORD = os.environ["GMAIL_APP_PASSWORD"]
TO_EMAIL          = "lbaldwin08@gmail.com"
DAYS_BACK         = 7

TARGET_FIRM_PATTERNS = [
    "skadden", "latham", "kirkland", "sidley", "jones day",
    "baker mckenzie", "baker & mckenzie", "weil gotshal", "weil,",
    "paul weiss", "paul, weiss", "davis polk", "simpson thacher",
    "cleary gottlieb", "cleary,", "sullivan & cromwell", "sullivan and cromwell",
    "cravath", "debevoise", "willkie farr", "willkie,", "proskauer",
    "white & case", "gibson dunn", "o'melveny", "omelveny",
    "mayer brown", "dechert", "arnold & porter", "morgan lewis",
    "covington & burling", "covington,", "hogan lovells", "milbank",
    "cahill gordon", "cahill,",
]

# Workday configs: (tenant, job_site, display_name)
WORKDAY_FIRMS = [
    ("weil",                   "work_at_weil",  "Weil Gotshal & Manges"),
    ("skadden",                "External",      "Skadden Arps"),
    ("lw",                     "LW",            "Latham & Watkins"),
    ("simpsonthacherbartlett", "External",      "Simpson Thacher & Bartlett"),
    ("morganlewis",            "External",      "Morgan Lewis"),
    ("hoganllovells",          "External",      "Hogan Lovells"),
    ("dechert",                "External",      "Dechert"),
    ("arnoldporter",           "External",      "Arnold & Porter"),
    ("mayerbrown",             "External",      "Mayer Brown"),
    ("gibsondunn",             "External",      "Gibson Dunn"),
    ("davispolkwardwell",      "External",      "Davis Polk"),
    ("clearygottlieb",         "External",      "Cleary Gottlieb"),
    ("whitecase",              "External",      "White & Case"),
    ("milbank",                "External",      "Milbank"),
    ("proskauer",              "External",      "Proskauer Rose"),
    ("willkie",                "External",      "Willkie Farr"),
    ("cravath",                "External",      "Cravath"),
    ("debevoise",              "External",      "Debevoise & Plimpton"),
]

HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
        "AppleWebKit/537.36 (KHTML, like Gecko) "
        "Chrome/120.0.0.0 Safari/537.36"
    )
}

# ── Helpers ───────────────────────────────────────────────────────────────────

def is_target_firm(company: str) -> bool:
    lower = company.lower()
    return any(p in lower for p in TARGET_FIRM_PATTERNS)


def deduplicate(jobs: list) -> list:
    seen = set()
    unique = []
    for job in jobs:
        key = job.get("link", "").split("?")[0]  # ignore query params
        if key and key not in seen:
            seen.add(key)
            unique.append(job)
    return unique

# ── Job Search ────────────────────────────────────────────────────────────────

def search_indeed_rss(query: str) -> list:
    jobs = []
    try:
        params = urllib.parse.urlencode({
            "q":       query,
            "sort":    "date",
            "fromage": str(DAYS_BACK),
            "limit":   "50",
        })
        url  = f"https://www.indeed.com/rss?{params}"
        resp = requests.get(url, headers=HEADERS, timeout=20)
        resp.raise_for_status()

        root = ET.fromstring(resp.text)
        ns   = {"content": "http://purl.org/rss/1.0/modules/content/"}

        for item in root.findall(".//item"):
            title   = (item.findtext("title") or "").strip()
            link    = (item.findtext("link")  or "").strip()
            pub     = (item.findtext("pubDate") or "").strip()
            source  = item.find("source")
            company = (source.text if source is not None else "").strip()

            # Try extracting company from title if source is blank
            if not company:
                m = re.search(r" - (.+?) - ", title)
                if m:
                    company = m.group(1)

            # Location sometimes in parentheses at end of title
            location = ""
            m = re.search(r"\(([^)]+)\)\s*$", title)
            if m:
                location = m.group(1)

            jobs.append({
                "title":    title,
                "company":  company,
                "location": location,
                "date":     pub,
                "link":     link,
                "source":   "Indeed",
            })
    except Exception as e:
        print(f"  [WARN] Indeed RSS failed for '{query}': {e}")
    return jobs


def search_workday(tenant: str, job_site: str, firm_name: str) -> list:
    jobs = []
    try:
        url  = f"https://{tenant}.wd1.myworkdayjobs.com/wday/cxs/{tenant}/{job_site}/jobs"
        body = {"limit": 20, "offset": 0, "searchText": "library librarian research knowledge management"}
        resp = requests.post(url, json=body, timeout=15)
        resp.raise_for_status()
        data = resp.json()

        for posting in data.get("jobPostings", []):
            ext_path = posting.get("externalPath", "")
            jobs.append({
                "title":    posting.get("title", ""),
                "company":  firm_name,
                "location": posting.get("locationsText", ""),
                "date":     posting.get("postedOn", ""),
                "link":     f"https://{tenant}.wd1.myworkdayjobs.com/en-US/{job_site}/job/{ext_path}",
                "source":   "Workday",
            })
    except Exception:
        pass  # silently skip unavailable portals
    return jobs



def get_all_jobs() -> list:
    all_jobs = []

    # Indeed RSS
    queries = [
        'law firm librarian "research manager" "knowledge management"',
        '"research services manager" law firm library',
        'law firm library librarian research attorney',
        '"knowledge management" librarian legal',
    ]
    indeed_count = 0
    for q in queries:
        results = search_indeed_rss(q)
        all_jobs.extend(results)
        indeed_count += len(results)
    print(f"  Indeed: {indeed_count} raw results")

    # Workday portals
    wd_count = 0
    for tenant, job_site, firm_name in WORKDAY_FIRMS:
        results = search_workday(tenant, job_site, firm_name)
        all_jobs.extend(results)
        wd_count += len(results)
    print(f"  Workday: {wd_count} results from {len(WORKDAY_FIRMS)} firm portals")

    # Deduplicate then filter to target firms
    unique   = deduplicate(all_jobs)
    filtered = [j for j in unique if is_target_firm(j["company"])]
    print(f"  Matched {len(filtered)} job(s) at target firms")
    return filtered

# ── HTML Generation ───────────────────────────────────────────────────────────

CSS = """
<style>
  body{font-family:Georgia,serif;max-width:840px;margin:0 auto;padding:22px;background:#f9f9f6;color:#222}
  h1{background:#1a3a5c;color:#fff;padding:16px 20px;border-radius:4px;font-size:1.35em;margin-bottom:4px}
  .sub{color:#666;font-size:.9em;margin-bottom:22px}
  .summary{background:#eef3f8;border:1px solid #bcd;border-radius:4px;padding:12px 16px;margin-bottom:24px;font-size:.93em}
  h2{border-bottom:2px solid #1a3a5c;color:#1a3a5c;padding-bottom:3px;margin-top:28px;font-size:1.1em}
  .job{background:#fff;border:1px solid #dde3ea;border-left:5px solid #1a3a5c;border-radius:3px;padding:12px 16px;margin:10px 0}
  .jt{font-size:1.05em;font-weight:bold;color:#1a3a5c}
  .jm{color:#666;font-size:.87em;margin:3px 0 7px}
  .ja a{color:#c0392b;font-size:.88em;text-decoration:none}
  .none{color:#999;font-style:italic;font-size:.9em;padding:6px 0}
  .li-btn{display:inline-block;margin:24px 0 8px;background:#0a66c2;color:#fff;padding:10px 20px;border-radius:4px;text-decoration:none;font-size:.95em;font-family:Arial,sans-serif}
  footer{border-top:1px solid #ccc;margin-top:36px;padding-top:10px;color:#999;font-size:.8em}
</style>
"""


def build_html(jobs: list, run_date: str) -> str:
    # Group by company
    by_firm: dict[str, list] = {}
    for job in jobs:
        by_firm.setdefault(job["company"], []).append(job)

    count   = len(jobs)
    summary = (
        f"<strong>{count} position(s)</strong> found across "
        f"<strong>{len(by_firm)}</strong> firm(s) this week."
        if count > 0 else
        "No new library, research, or knowledge management openings "
        "found at the 27 target firms this week."
    )

    sections = ""
    for firm, firm_jobs in sorted(by_firm.items()):
        sections += f"<h2>{escape(firm)}</h2>\n"
        for job in firm_jobs:
            loc_str  = f" &nbsp;|&nbsp; {escape(job['location'])}" if job["location"] else ""
            date_str = f" &nbsp;|&nbsp; {escape(job['date'])}"     if job["date"]     else ""
            sections += f"""<div class="job">
  <div class="jt">{escape(job['title'])}</div>
  <div class="jm">{escape(job['company'])}{loc_str}{date_str} &nbsp;|&nbsp; via {job['source']}</div>
  <div class="ja"><a href="{escape(job['link'])}">View &amp; Apply &rarr;</a></div>
</div>\n"""

    if not sections:
        sections = "<p class='none'>No openings found at the 27 target firms this week. Check back next Monday.</p>"

    return f"""<!DOCTYPE html>
<html lang="en">
<head><meta charset="UTF-8"><title>Law Firm Library &amp; Research Jobs – {run_date}</title>{CSS}</head>
<body>
<h1>Law Firm Library &amp; Research Jobs</h1>
<div class="sub">Week of <strong>{run_date}</strong> &nbsp;|&nbsp; 27 Skadden peer firms monitored</div>
<div class="summary">{summary}</div>
{sections}
<h2>LinkedIn</h2>
<p style="font-size:.9em;color:#444">Your personalized LinkedIn results require you to be signed in. Click below to open your search directly:</p>
<a class="li-btn" href="https://www.linkedin.com/jobs/search/?keywords=law+firm+research&f_TPR=r604800">Search LinkedIn: "law firm research" (Past Week) &rarr;</a>
<footer>
  Generated by GitHub Actions &nbsp;|&nbsp; {run_date} &nbsp;|&nbsp;
  Sources: Indeed RSS, LinkedIn, firm Workday portals &nbsp;|&nbsp;
  Next run: next Monday ~7 AM ET
</footer>
</body>
</html>"""

# ── Email ─────────────────────────────────────────────────────────────────────

def send_email(subject: str, html_body: str) -> None:
    msg = MIMEMultipart("alternative")
    msg["Subject"] = subject
    msg["From"]    = GMAIL_ADDRESS
    msg["To"]      = TO_EMAIL
    msg.attach(MIMEText(html_body, "html"))

    with smtplib.SMTP("smtp.gmail.com", 587) as smtp:
        smtp.ehlo()
        smtp.starttls()
        smtp.login(GMAIL_ADDRESS, GMAIL_APP_PASSWORD)
        smtp.sendmail(GMAIL_ADDRESS, TO_EMAIL, msg.as_string())

# ── Entry Point ───────────────────────────────────────────────────────────────

def main() -> None:
    run_date = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    print(f"\nLaw Firm Library Job Newsletter  –  {run_date}")
    print("=" * 50)

    print("[1/3] Searching for jobs...")
    jobs = get_all_jobs()

    print("[2/3] Building newsletter...")
    html = build_html(jobs, run_date)

    count   = len(jobs)
    subject = (
        f"[{run_date}] Law Firm Library Jobs — {count} new opening(s) found"
        if count > 0 else
        f"[{run_date}] Law Firm Library Jobs — No new openings this week"
    )

    print(f"[3/3] Sending email to {TO_EMAIL}...")
    send_email(subject, html)
    print("Done!\n")


if __name__ == "__main__":
    main()
