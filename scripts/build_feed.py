#!/usr/bin/env python3
"""Pull SDR / BDR / AE openings from public company job boards and write feed.json."""

from __future__ import annotations

import argparse
import html
import json
import re
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
COMPANIES_PATH = ROOT / "scripts" / "companies.json"
UA = "HiintelFeedBuilder/1.0 (+https://github.com/azealcompany-dev/hiintel)"

TAG_RE = re.compile(r"<[^>]+>")
WS_RE = re.compile(r"\s+")
SLUG_RE = re.compile(r"[^a-z0-9]+")

# Title must look like these families. Keep intern/manager noise out.
FAMILY_RULES = [
    (
        "SDR",
        re.compile(
            r"\b(sdr|sales development(?: representative)?|outbound sales development)\b",
            re.I,
        ),
    ),
    (
        "BDR",
        re.compile(
            r"\b(bdr|business development representative)\b",
            re.I,
        ),
    ),
    (
        "AE",
        re.compile(
            r"\b(account executive|\bae\b|enterprise ae|commercial ae|mid[- ]market ae)\b",
            re.I,
        ),
    ),
]
EXCLUDE = re.compile(
    r"\b(intern|internship|recruiting coordinator|software engineer|engineering manager)\b",
    re.I,
)


def classify(title: str) -> str | None:
    if EXCLUDE.search(title):
        return None
    for family, pattern in FAMILY_RULES:
        if pattern.search(title):
            return family
    return None


def strip_html(value: str, limit: int = 280) -> str:
    text = html.unescape(TAG_RE.sub(" ", value or ""))
    text = WS_RE.sub(" ", text).strip()
    if len(text) <= limit:
        return text
    return text[: limit - 1].rstrip() + "…"


def is_priority_location(location: str) -> bool:
    loc = location.lower()
    needles = (
        "united states",
        "usa",
        "u.s.",
        "us remote",
        "remote us",
        "remote - us",
        "new york",
        "san francisco",
        "austin",
        "seattle",
        "chicago",
        "boston",
        "denver",
        "atlanta",
        "los angeles",
        "miami",
    )
    if any(n in loc for n in needles):
        return True
    if re.search(r",\s*(al|ak|az|ar|ca|co|ct|dc|de|fl|ga|hi|ia|id|il|in|ks|ky|la|ma|md|me|mi|mn|mo|ms|mt|nc|nd|ne|nh|nj|nm|nv|ny|oh|ok|or|pa|ri|sc|sd|tn|tx|ut|va|vt|wa|wi|wv)\b", loc, re.I):
        return True
    return loc.strip() in {"remote", "united states"}


def cap_openings(openings: list[dict]) -> list[dict]:
    """Keep the list useful: 8 roles per company, 80 per family."""
    per_company: dict[str, int] = {}
    per_family: dict[str, int] = {}
    kept: list[dict] = []
    for job in openings:
        company = job["company"]
        family = job["roleFamily"]
        if per_company.get(company, 0) >= 8:
            continue
        if per_family.get(family, 0) >= 80:
            continue
        per_company[company] = per_company.get(company, 0) + 1
        per_family[family] = per_family.get(family, 0) + 1
        kept.append(job)
    return kept


def slug(value: str) -> str:
    return SLUG_RE.sub("-", value.lower()).strip("-")


def fetch_json(url: str, timeout: int = 20) -> object | None:
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            if resp.status != 200:
                return None
            return json.loads(resp.read().decode("utf-8"))
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError, ValueError):
        return None


def greenhouse_jobs(company: dict) -> list[dict]:
    token = company["board"]
    payload = fetch_json(
        f"https://boards-api.greenhouse.io/v1/boards/{token}/jobs?content=true"
    )
    jobs = []
    if not isinstance(payload, dict):
        return jobs
    for job in payload.get("jobs") or []:
        title = str(job.get("title") or "")
        family = classify(title)
        if not family:
            continue
        loc = ""
        location = job.get("location")
        if isinstance(location, dict):
            loc = str(location.get("name") or "")
        elif isinstance(location, str):
            loc = location
        posted = str(job.get("updated_at") or job.get("created_at") or "")[:10]
        jid = str(job.get("id") or "")
        jobs.append(
            {
                "id": f"{slug(company['name'])}-{slug(title)}-{jid}",
                "company": company["name"],
                "role": title.strip(),
                "roleFamily": family,
                "location": loc,
                "url": str(job.get("absolute_url") or ""),
                "lookingFor": strip_html(str(job.get("content") or "")),
                "companyBrief": f"{company['name']} opening listed on their Greenhouse board.",
                "postedAt": posted,
            }
        )
    return jobs


def lever_jobs(company: dict) -> list[dict]:
    payload = fetch_json(f"https://api.lever.co/v0/postings/{company['board']}?mode=json")
    jobs = []
    if not isinstance(payload, list):
        return jobs
    for job in payload:
        title = str(job.get("text") or "")
        family = classify(title)
        if not family:
            continue
        cats = job.get("categories") if isinstance(job.get("categories"), dict) else {}
        loc = str(cats.get("location") or "")
        created = job.get("createdAt")
        posted = ""
        if isinstance(created, (int, float)):
            posted = datetime.fromtimestamp(created / 1000, tz=timezone.utc).date().isoformat()
        jid = str(job.get("id") or "")
        jobs.append(
            {
                "id": f"{slug(company['name'])}-{slug(title)}-{jid[:12]}",
                "company": company["name"],
                "role": title.strip(),
                "roleFamily": family,
                "location": loc,
                "url": str(job.get("hostedUrl") or job.get("applyUrl") or ""),
                "lookingFor": strip_html(str(job.get("descriptionPlain") or "")),
                "companyBrief": f"{company['name']} opening listed on their Lever board.",
                "postedAt": posted,
            }
        )
    return jobs


def ashby_jobs(company: dict) -> list[dict]:
    payload = fetch_json(
        f"https://api.ashbyhq.com/posting-api/job-board/{company['board']}"
    )
    jobs = []
    listings = []
    if isinstance(payload, dict):
        listings = payload.get("jobs") or payload.get("jobPostings") or []
    if not isinstance(listings, list):
        return jobs
    for job in listings:
        title = str(job.get("title") or job.get("jobTitle") or "")
        family = classify(title)
        if not family:
            continue
        loc = ""
        location = job.get("location")
        if isinstance(location, str):
            loc = location
        elif isinstance(location, dict):
            loc = str(location.get("locationName") or location.get("name") or "")
        posted = str(job.get("publishedAt") or job.get("updatedAt") or "")[:10]
        jid = str(job.get("id") or job.get("jobId") or "")
        url = str(job.get("jobUrl") or job.get("applyUrl") or "")
        jobs.append(
            {
                "id": f"{slug(company['name'])}-{slug(title)}-{slug(jid)[:16]}",
                "company": company["name"],
                "role": title.strip(),
                "roleFamily": family,
                "location": loc,
                "url": url,
                "lookingFor": strip_html(str(job.get("descriptionPlain") or job.get("descriptionHtml") or "")),
                "companyBrief": f"{company['name']} opening listed on their Ashby board.",
                "postedAt": posted,
            }
        )
    return jobs


FETCHERS = {
    "greenhouse": greenhouse_jobs,
    "lever": lever_jobs,
    "ashby": ashby_jobs,
}


def build(companies: list[dict]) -> dict:
    openings: list[dict] = []
    seen: set[str] = set()
    for company in companies:
        ats = company.get("ats")
        fetcher = FETCHERS.get(ats)
        if not fetcher:
            print(f"skip {company.get('name')}: unknown ats {ats}", file=sys.stderr)
            continue
        try:
            jobs = fetcher(company)
        except Exception as exc:  # noqa: BLE001
            print(f"fail {company.get('name')}: {exc}", file=sys.stderr)
            jobs = []
        print(f"{company['name']} ({ats}): {len(jobs)} sales roles", file=sys.stderr)
        for job in jobs:
            key = job["id"]
            if key in seen or not job.get("url"):
                continue
            seen.add(key)
            openings.append(job)
        time.sleep(0.15)

    family_order = {"SDR": 0, "BDR": 1, "AE": 2}
    openings.sort(
        key=lambda job: (
            0 if is_priority_location(job.get("location") or "") else 1,
            family_order.get(job["roleFamily"], 9),
            job["company"].lower(),
            job["role"].lower(),
        )
    )
    openings = cap_openings(openings)
    return {
        "updatedAt": datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds"),
        "openings": openings,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Build Hiintel SDR/BDR/AE feed.json")
    parser.add_argument("--companies", type=Path, default=COMPANIES_PATH)
    parser.add_argument("--out", type=Path, default=ROOT / "feed.json")
    args = parser.parse_args()

    companies = json.loads(args.companies.read_text())
    feed = build(companies)
    args.out.write_text(json.dumps(feed, indent=2, ensure_ascii=False) + "\n")
    counts: dict[str, int] = {}
    for job in feed["openings"]:
        counts[job["roleFamily"]] = counts.get(job["roleFamily"], 0) + 1
    print(
        f"Wrote {len(feed['openings'])} openings "
        f"({', '.join(f'{k} {v}' for k, v in sorted(counts.items()))}) -> {args.out}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
