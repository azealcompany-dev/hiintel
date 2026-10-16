#!/usr/bin/env python3
"""Fail when feed.json is invalid, small, stale, or full of dead job links."""

from __future__ import annotations

import json
import random
import sys
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MIN_OPENINGS = 300
MAX_AGE_HOURS = 12
SAMPLE_SIZE = 15
# Fail only when dead links are more than 20% of the sample (3/15 passes).
MAX_DEAD_PERCENT = 20
TIMEOUT_SECONDS = 15
UA = "HiintelFeedCheck/1.0 (+https://github.com/azealcompany-dev/hiintel)"


def fail(message: str) -> None:
    print(f"::error::{message}")
    print(f"feed check failed: {message}", file=sys.stderr)
    raise SystemExit(1)


def exceeds_dead_limit(dead_count: int, sample_size: int) -> bool:
    return dead_count * 100 > sample_size * MAX_DEAD_PERCENT


def load_feed(path: Path) -> dict:
    try:
        raw = path.read_text(encoding="utf-8")
    except OSError as exc:
        fail(f"{path} could not be read ({exc})")
    try:
        data = json.loads(raw)
    except json.JSONDecodeError as exc:
        fail(f"{path} is not valid JSON ({exc})")
    if not isinstance(data, dict) or not isinstance(data.get("openings"), list):
        fail(f"{path} is missing the openings list")
    return data


def parse_updated_at(value: object) -> datetime:
    if not isinstance(value, str) or not value.strip():
        fail("updatedAt is missing")
    text = value.strip()
    if text.endswith("Z"):
        text = text[:-1] + "+00:00"
    try:
        parsed = datetime.fromisoformat(text)
    except ValueError:
        fail(f"updatedAt is not a timestamp ({value})")
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


def job_urls(openings: list) -> list[str]:
    found = []
    seen = set()
    for job in openings:
        if not isinstance(job, dict):
            continue
        url = job.get("url")
        if not isinstance(url, str):
            continue
        url = url.strip()
        if url in seen or not url.startswith(("http://", "https://")):
            continue
        seen.add(url)
        found.append(url)
    return found


def status_code(url: str) -> int | None:
    request = urllib.request.Request(
        url,
        headers={"User-Agent": UA, "Accept": "text/html"},
        method="GET",
    )
    try:
        response = urllib.request.urlopen(request, timeout=TIMEOUT_SECONDS)
    except urllib.error.HTTPError as exc:
        return exc.code
    except (urllib.error.URLError, TimeoutError, OSError, ValueError):
        return None
    try:
        return response.getcode()
    finally:
        response.close()


def main() -> int:
    path = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "feed.json"
    feed = load_feed(path)
    openings = feed["openings"]
    if len(openings) < MIN_OPENINGS:
        fail(f"only {len(openings)} openings (need at least {MIN_OPENINGS})")

    updated = parse_updated_at(feed.get("updatedAt"))
    age_hours = (datetime.now(timezone.utc) - updated).total_seconds() / 3600
    if age_hours > MAX_AGE_HOURS:
        fail(f"updatedAt is {age_hours:.1f} hours old (limit {MAX_AGE_HOURS})")

    urls = job_urls(openings)
    if len(urls) < SAMPLE_SIZE:
        noun = "job URL" if len(urls) == 1 else "job URLs"
        fail(f"only {len(urls)} {noun} to sample (need {SAMPLE_SIZE})")

    sample = random.sample(urls, SAMPLE_SIZE)
    dead = []
    for url in sample:
        code = status_code(url)
        if code in (404, 410):
            dead.append(url)
            print(f"dead {code} {url}")
        else:
            label = "no-status" if code is None else str(code)
            print(f"ok {label} {url}")

    if exceeds_dead_limit(len(dead), SAMPLE_SIZE):
        fail(
            f"{len(dead)} of {SAMPLE_SIZE} sampled job URLs returned 404 or 410 "
            f"(more than {MAX_DEAD_PERCENT}%)"
        )

    print(
        f"feed ok: {len(openings)} openings, updatedAt {age_hours:.1f}h old, "
        f"dead links {len(dead)}/{SAMPLE_SIZE}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
