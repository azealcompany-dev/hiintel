#!/usr/bin/env python3
"""Probe public Greenhouse / Lever / Ashby JSON boards. No HTML scraping."""

from __future__ import annotations

import argparse
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
CANDIDATES_PATH = ROOT / "scripts" / "candidates.json"
HEALTH_PATH = ROOT / "scripts" / "board_health.json"
UA = "HiintelBoardProbe/1.0 (+https://github.com/azealcompany-dev/hiintel)"

SALES_RE = re.compile(
    r"\b(sdr|bdr|account executive|\bae\b|sales development(?: representative)?|"
    r"outbound sales development|enterprise ae|commercial ae|mid[- ]market ae)\b",
    re.I,
)
EXCLUDE = re.compile(
    r"\b(intern|internship|recruiting coordinator|software engineer|engineering manager)\b",
    re.I,
)
SLUG_RE = re.compile(r"[^a-z0-9]+")

ATS_URLS = {
    "greenhouse": "https://boards-api.greenhouse.io/v1/boards/{token}/jobs",
    "lever": "https://api.lever.co/v0/postings/{token}?mode=json",
    "ashby": "https://api.ashbyhq.com/posting-api/job-board/{token}",
}
ATS_ORDER = ("greenhouse", "lever", "ashby")


def slugify(name: str) -> str:
    return SLUG_RE.sub("-", name.lower()).strip("-")


def guess_slugs(name: str, extra: list[str] | None = None) -> list[str]:
    dashed = slugify(name)
    compact = SLUG_RE.sub("", name.lower())
    variants = [
        dashed,
        compact,
        f"{compact}inc",
    ]
    if extra:
        variants = list(extra) + variants
    seen: set[str] = set()
    out: list[str] = []
    for item in variants:
        token = (item or "").strip().lower()
        if not token or token in seen:
            continue
        seen.add(token)
        out.append(token)
    return out


def titles_from_payload(ats: str, payload: object) -> list[str]:
    titles: list[str] = []
    if ats == "greenhouse" and isinstance(payload, dict):
        for job in payload.get("jobs") or []:
            if isinstance(job, dict):
                titles.append(str(job.get("title") or ""))
    elif ats == "lever" and isinstance(payload, list):
        for job in payload:
            if isinstance(job, dict):
                titles.append(str(job.get("text") or job.get("title") or ""))
    elif ats == "ashby" and isinstance(payload, dict):
        listings = payload.get("jobs") or payload.get("jobPostings") or []
        if isinstance(listings, list):
            for job in listings:
                if isinstance(job, dict):
                    titles.append(str(job.get("title") or job.get("jobTitle") or ""))
    return titles


def sales_count(titles: list[str]) -> int:
    n = 0
    for title in titles:
        if EXCLUDE.search(title):
            continue
        if SALES_RE.search(title):
            n += 1
    return n


def fetch(ats: str, token: str, timeout: int = 12) -> tuple[int | str, int]:
    url = ATS_URLS[ats].format(token=token)
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            status = int(resp.status)
            if status != 200:
                return status, 0
            payload = json.loads(resp.read().decode("utf-8"))
            return status, sales_count(titles_from_payload(ats, payload))
    except urllib.error.HTTPError as exc:
        return int(exc.code), 0
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError, ValueError):
        return "error", 0


def probe_tokens(name: str, tokens: list[str], delay: float) -> dict:
    """Try GH, Lever, Ashby for each token. Stop at the first HTTP 200."""
    last = {
        "company": name,
        "ats": "",
        "token": tokens[0] if tokens else "",
        "http": 404,
        "sales_jobs": 0,
    }
    for token in tokens:
        for ats in ATS_ORDER:
            time.sleep(delay)
            status, sales = fetch(ats, token)
            last = {
                "company": name,
                "ats": ats,
                "token": token,
                "http": status,
                "sales_jobs": sales,
            }
            if status == 200:
                return last
    return last


def load_json(path: Path, default):
    if not path.exists():
        return default
    return json.loads(path.read_text())


def existing_rows(companies: list[dict], delay: float) -> list[dict]:
    rows: list[dict] = []
    for company in companies:
        name = str(company.get("name") or "")
        known = str(company.get("board") or "")
        extra = [known] if known else []
        tokens = guess_slugs(name, extra)
        # Prefer the recorded ATS first by probing that token on that ATS, then fall through.
        recorded_ats = str(company.get("ats") or "")
        if known and recorded_ats in ATS_URLS:
            time.sleep(delay)
            status, sales = fetch(recorded_ats, known)
            if status == 200:
                rows.append(
                    {
                        "company": name,
                        "ats": recorded_ats,
                        "token": known,
                        "http": status,
                        "sales_jobs": sales,
                    }
                )
                continue
        rows.append(probe_tokens(name, tokens, delay))
        print(
            f"retry {name}: {rows[-1]['ats']} {rows[-1]['token']} "
            f"http={rows[-1]['http']} sales={rows[-1]['sales_jobs']}",
            file=sys.stderr,
        )
    return rows


def candidate_rows(candidates: list[dict], skip_names: set[str], delay: float) -> list[dict]:
    rows: list[dict] = []
    for item in candidates:
        name = str(item.get("name") or "")
        if not name or name.lower() in skip_names:
            continue
        extra = item.get("slugs") if isinstance(item.get("slugs"), list) else []
        extra_s = [str(s) for s in extra]
        rows.append(probe_tokens(name, guess_slugs(name, extra_s), delay))
    return rows


def print_table(rows: list[dict]) -> None:
    width = max((len(r["company"]) for r in rows), default=7)
    header = f"{'company':<{width}}  {'ats':<11}  {'token':<22}  {'http':<6}  sales_jobs"
    print(header)
    print("-" * len(header))
    for row in rows:
        print(
            f"{row['company']:<{width}}  {str(row['ats'] or '-'):<11}  "
            f"{str(row['token'] or '-'):<22}  {str(row['http']):<6}  {row['sales_jobs']}"
        )


def merge_companies(live: list[dict]) -> list[dict]:
    merged: list[dict] = []
    seen: set[str] = set()
    for row in live:
        key = row["company"].lower()
        if key in seen:
            continue
        if row.get("http") != 200 or int(row.get("sales_jobs") or 0) <= 0:
            continue
        seen.add(key)
        merged.append(
            {
                "name": row["company"],
                "ats": row["ats"],
                "board": row["token"],
            }
        )
    merged.sort(key=lambda c: c["name"].lower())
    return merged


def main() -> int:
    parser = argparse.ArgumentParser(description="Probe public GH / Lever / Ashby boards.")
    parser.add_argument("--companies", type=Path, default=COMPANIES_PATH)
    parser.add_argument("--candidates", type=Path, default=CANDIDATES_PATH)
    parser.add_argument("--health", type=Path, default=HEALTH_PATH)
    parser.add_argument("--merge", action="store_true", help="Rewrite companies.json from live boards.")
    parser.add_argument("--delay", type=float, default=0.2)
    args = parser.parse_args()

    companies = load_json(args.companies, [])
    candidates = load_json(args.candidates, [])
    if not isinstance(companies, list):
        companies = []
    if not isinstance(candidates, list):
        candidates = []

    print(f"Probing {len(companies)} current companies…", file=sys.stderr)
    current = existing_rows(companies, args.delay)
    skip = {c.get("name", "").lower() for c in companies}
    print(f"Probing {len(candidates)} candidates…", file=sys.stderr)
    extras = candidate_rows(candidates, skip, args.delay)
    rows = current + extras
    print_table(rows)

    n404 = sum(1 for r in rows if r.get("http") == 404)
    nzero = sum(1 for r in rows if r.get("http") == 200 and int(r.get("sales_jobs") or 0) == 0)
    nlive = sum(1 for r in rows if r.get("http") == 200 and int(r.get("sales_jobs") or 0) > 0)
    merged = merge_companies(rows)
    health = {
        "updatedAt": datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds"),
        "summary": {
            "probed": len(rows),
            "http_404": n404,
            "zero_sales": nzero,
            "live_sales": nlive,
            "merged": len(merged),
        },
        "rows": rows,
    }
    args.health.write_text(json.dumps(health, indent=2, ensure_ascii=False) + "\n")
    print(
        f"404={n404}  zero-sales={nzero}  live-sales={nlive}  merged={len(merged)}  "
        f"health={args.health}",
        file=sys.stderr,
    )
    if args.merge:
        args.companies.write_text(json.dumps(merged, indent=2, ensure_ascii=False) + "\n")
        print(f"Wrote {len(merged)} companies -> {args.companies}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
