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
MANAGERS_PATH = ROOT / "scripts" / "managers.json"
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


def strip_html(value: str, limit: int | None = 280) -> str:
    text = html.unescape(TAG_RE.sub(" ", value or ""))
    text = text.replace("&nbsp", " ").replace("&amp", "&").replace("&nbsp;", " ")
    text = WS_RE.sub(" ", text).strip()
    if limit is None or len(text) <= limit:
        return text
    return text[: limit - 1].rstrip() + "…"


EMAIL_RE = re.compile(r"\b\S+@\S+\b")
PHONE_RE = re.compile(r"(?:\+?\d[\d\-\s().]{7,}\d)")
TITLE_HINT = re.compile(
    r"\b(manager|director|head|vp|vice president)\b",
    re.I,
)
LEAD_IN = re.compile(
    r"(?:"
    r"this role reports to|"
    r"this position reports to|"
    r"you(?:['’]ll| will) report(?:s)? to|"
    r"reporting to|"
    r"reports to|"
    r"hiring manager(?:\s+is)?"
    r")\s*[:\-–]?\s+",
    re.I,
)
WORK_WITH = re.compile(r"you(?:['’]ll| will) work with\s+", re.I)
NAME_STOP = {
    "sales", "development", "business", "account", "executive", "manager",
    "director", "head", "vp", "vice", "president", "team", "role", "hiring",
    "representative", "outbound", "enterprise", "commercial", "the", "our",
    "your", "global", "senior", "associate", "lead", "chief", "officer",
    "revenue", "growth", "sdr", "bdr", "ae", "this", "that", "their",
}


def scrub_contact(value: str) -> str:
    value = EMAIL_RE.sub(" ", value or "")
    value = PHONE_RE.sub(" ", value)
    return WS_RE.sub(" ", value).strip(" ,;:-–")


def is_person_name(text: str) -> bool:
    parts = [p for p in (text or "").split() if p]
    if not (2 <= len(parts) <= 3):
        return False
    for part in parts:
        if not part.isalpha():
            return False
        if part.lower() in NAME_STOP:
            return False
        if not (part[0].isupper() and part[1:].islower()):
            return False
    return True


def clause_after(match: re.Match[str], text: str) -> str:
    rest = text[match.end() :]
    stop = re.search(r"[\.;\n]", rest)
    clause = rest[: stop.start()] if stop else rest
    return scrub_contact(clause)[:120]


def clean_title(value: str) -> str:
    value = scrub_contact(value)
    value = re.sub(r"^(the|our|your)\s+", "", value, flags=re.I).strip()
    value = re.split(
        r"\b(?:you(?:['’]ll| will| are)|you['’]re|and then|who |based |to help|to own|to drive)\b",
        value,
        maxsplit=1,
        flags=re.I,
    )[0]
    value = re.sub(r"\s+on\s+[A-Za-z][A-Za-z\-]*$", "", value)
    value = re.sub(r"^(?:a|an|the|our|your)\s+", "", value, flags=re.I).strip()
    return WS_RE.sub(" ", value).strip(" ,;:-–")[:80]


def parse_manager_clause(clause: str) -> dict | None:
    clause = clean_title(clause)
    if not clause:
        return None
    if "," in clause:
        left, right = [p.strip() for p in clause.split(",", 1)]
        if is_person_name(left) and TITLE_HINT.search(right):
            return {"name": left, "title": clean_title(right)}
    parts = clause.split()
    if (
        len(parts) >= 4
        and is_person_name(" ".join(parts[:2]))
        and TITLE_HINT.search(" ".join(parts[2:]))
    ):
        return {"name": " ".join(parts[:2]), "title": clean_title(" ".join(parts[2:]))}
    if TITLE_HINT.search(clause):
        title = clean_title(clause)
        if title:
            return {"title": title}
    return None


def extract_from_jd(plain: str) -> dict | None:
    """Pull a name/title only when the JD actually says so. Never invent a name."""
    if not plain:
        return None
    for match in LEAD_IN.finditer(plain):
        parsed = parse_manager_clause(clause_after(match, plain))
        if parsed:
            return parsed
    for match in WORK_WITH.finditer(plain):
        clause = clause_after(match, plain)
        if not TITLE_HINT.search(clause):
            continue
        parsed = parse_manager_clause(clause)
        if parsed:
            return parsed
    return None


def roster_lookup(roster: dict, company: str, family: str) -> dict | None:
    entry = ((roster.get(company) or {}).get(family) or {})
    if not isinstance(entry, dict):
        return None
    title = scrub_contact(str(entry.get("title") or ""))
    name = scrub_contact(str(entry.get("name") or ""))
    if name and (EMAIL_RE.search(name) or PHONE_RE.search(name) or not is_person_name(name)):
        name = ""
    if not title and not name:
        return None
    out: dict[str, str] = {"source": "roster"}
    if title:
        out["title"] = title
    if name:
        out["name"] = name
    if "title" not in out:
        return None
    return out


def attach_hiring_manager(job: dict, plain: str, roster: dict) -> None:
    from_jd = extract_from_jd(plain)
    from_roster = roster_lookup(roster, job["company"], job["roleFamily"])
    result: dict[str, str] | None = None
    if from_jd:
        title = from_jd.get("title") or (from_roster or {}).get("title")
        if not title:
            return
        result = {"title": title, "source": "jd"}
        if from_jd.get("name"):
            result["name"] = from_jd["name"]
    elif from_roster:
        result = from_roster
    if not result:
        return
    blob = json.dumps(result)
    if "@" in blob or EMAIL_RE.search(blob) or PHONE_RE.search(blob):
        result.pop("name", None)
        if EMAIL_RE.search(result.get("title", "")) or PHONE_RE.search(result.get("title", "")):
            return
    result.pop("email", None)
    result.pop("phone", None)
    if "title" not in result:
        return
    job["hiringManager"] = result


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


def norm_title(value: str) -> str:
    text = SLUG_RE.sub(" ", (value or "").lower())
    return WS_RE.sub(" ", text).strip()


def opening_key(company: str, title: str) -> str:
    return f"{(company or '').lower()}|{norm_title(title)}"


def fetch_json(url: str, timeout: int = 20) -> tuple[object | None, str]:
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            if resp.status == 404:
                return None, "404"
            if resp.status != 200:
                return None, f"http {resp.status}"
            return json.loads(resp.read().decode("utf-8")), "ok"
    except urllib.error.HTTPError as exc:
        if exc.code == 404:
            return None, "404"
        return None, f"http {exc.code}"
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError, ValueError):
        return None, "error"


def numberish(value: object) -> float | None:
    if isinstance(value, bool):
        return None
    if isinstance(value, (int, float)):
        return float(value)
    if isinstance(value, str):
        cleaned = value.replace(",", "").strip()
        try:
            return float(cleaned)
        except ValueError:
            return None
    return None


def compensation_from_range(payload: object) -> dict | None:
    if not isinstance(payload, dict):
        return None
    min_v = numberish(payload.get("min") or payload.get("minValue") or payload.get("minimum"))
    max_v = numberish(payload.get("max") or payload.get("maxValue") or payload.get("maximum"))
    currency = str(
        payload.get("currency") or payload.get("currencyCode") or payload.get("currencySymbol") or ""
    ).strip() or None
    interval = str(payload.get("interval") or payload.get("period") or "").strip()
    if min_v is None and max_v is None:
        text = str(payload.get("title") or payload.get("text") or payload.get("summary") or "").strip()
        return {"text": text} if text else None
    parts: list[str] = []
    if min_v is not None and max_v is not None:
        parts.append(f"{int(min_v):,}–{int(max_v):,}")
    elif min_v is not None:
        parts.append(f"{int(min_v):,}+")
    elif max_v is not None:
        parts.append(f"up to {int(max_v):,}")
    if currency:
        parts.append(currency)
    if interval:
        parts.append(interval)
    out: dict[str, object] = {"text": " ".join(parts)}
    if min_v is not None:
        out["min"] = min_v
    if max_v is not None:
        out["max"] = max_v
    if currency:
        out["currency"] = currency
    return out


def classify_segment(title: str, team: str = "", department: str = "") -> str | None:
    blob = f"{title} {team} {department}".lower()
    if re.search(r"\benterprise\b|named account|strategic account", blob):
        return "Enterprise"
    if re.search(r"\bmid[- ]market\b|\bmidmarket\b|\bmm\b|commercial mid", blob):
        return "MM"
    if re.search(r"\bsmb\b|small business|small[- ]medium|velocity", blob):
        return "SMB"
    return None


def classify_workplace(location: str, flags: dict | None = None) -> str | None:
    flags = flags or {}
    loc = (location or "").lower()
    hybrid = bool(flags.get("hybrid")) or "hybrid" in loc
    remote = bool(flags.get("remote")) or "remote" in loc
    onsite = bool(flags.get("onsite"))
    if hybrid:
        return "hybrid"
    if remote:
        if re.search(r"\bglobal\b|\bworldwide\b|\bemea\b|\beurope\b|\bapac\b|\buk\b|\bcanada\b", loc):
            if "united states" in loc or re.search(r"\bus\b|\busa\b", loc):
                return "remoteUS"
            return "remoteGlobal"
        if is_priority_location(location) or "united states" in loc or re.search(r"\bus\b|\busa\b", loc):
            return "remoteUS"
        if loc.strip() in {"remote", "remote, united states", "united states - remote"}:
            return "remoteUS"
        return "remoteGlobal"
    if onsite or loc:
        return "onsite"
    return None


def extract_quota(plain: str) -> bool | None:
    if re.search(r"\bno quota\b|not quota", plain, re.I):
        return False
    if re.search(r"\bquota[- ]carrying\b|\bown(?:s|ing)? (?:a |your )?quota\b|\bagainst (?:a |your )?quota\b", plain, re.I):
        return True
    return None


def extract_ote(plain: str) -> str | None:
    match = re.search(
        r"(\bOTE\b[^.]{0,48}|\bon[- ]target earnings\b[^.]{0,48}|\$[\d,]{3,}(?:\s*[-–]\s*\$[\d,]{3,})?\s*\bOTE\b)",
        plain,
        re.I,
    )
    if not match:
        return None
    text = scrub_contact(match.group(1))
    return text[:80] or None


def extract_travel(plain: str) -> str | None:
    match = re.search(
        r"((?:up to\s+)?\d{1,2}\s*%\s*travel|travel\s+\d{1,2}\s*%|travel (?:up to )?\d{1,2}\s*%)",
        plain,
        re.I,
    )
    if not match:
        return None
    return scrub_contact(match.group(1))[:80] or None


def attach_extracts(job: dict, plain: str) -> None:
    quota = extract_quota(plain)
    if quota is not None:
        job["quotaCarrying"] = quota
    ote = extract_ote(plain)
    if ote:
        job["oteText"] = ote
    travel = extract_travel(plain)
    if travel:
        job["travelText"] = travel


def attach_optional(job: dict, key: str, value: object | None) -> None:
    if value is None or value == "":
        return
    job[key] = value


def load_previous(path: Path) -> dict:
    if not path.exists():
        return {}
    try:
        data = json.loads(path.read_text())
        return data if isinstance(data, dict) else {}
    except (OSError, json.JSONDecodeError):
        return {}


def mark_reposted(openings: list[dict], previous: dict) -> list[dict]:
    prev_openings = previous.get("openings") if isinstance(previous.get("openings"), list) else []
    prev_keys = {
        opening_key(str(job.get("company") or ""), str(job.get("role") or ""))
        for job in prev_openings
        if isinstance(job, dict)
    }
    prev_absent = previous.get("absent") if isinstance(previous.get("absent"), list) else []
    absent_keys = set()
    for item in prev_absent:
        if isinstance(item, dict):
            absent_keys.add(opening_key(str(item.get("company") or ""), str(item.get("title") or "")))
        elif isinstance(item, str):
            absent_keys.add(item)
    current_keys = {opening_key(job["company"], job["role"]) for job in openings}
    for job in openings:
        key = opening_key(job["company"], job["role"])
        if key in absent_keys and key in current_keys:
            job["reposted"] = True
    still_absent = sorted((absent_keys | prev_keys) - current_keys)
    return still_absent


def company_counts(openings: list[dict]) -> dict[str, dict[str, int]]:
    counts: dict[str, dict[str, int]] = {}
    for job in openings:
        bucket = counts.setdefault(job["company"], {})
        family = job.get("roleFamily") or ""
        if family:
            bucket[family] = bucket.get(family, 0) + 1
    return counts


def greenhouse_jobs(company: dict) -> tuple[list[dict], str]:
    token = company["board"]
    payload, health = fetch_json(
        f"https://boards-api.greenhouse.io/v1/boards/{token}/jobs?content=true"
    )
    jobs = []
    if health == "404":
        return jobs, "404"
    if not isinstance(payload, dict):
        return jobs, health if health != "ok" else "error"
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
        dept = ""
        departments = job.get("departments")
        if isinstance(departments, list) and departments:
            first = departments[0]
            if isinstance(first, dict):
                dept = str(first.get("name") or "")
        row = {
            "id": f"{slug(company['name'])}-{slug(title)}-{jid}",
            "company": company["name"],
            "role": title.strip(),
            "roleFamily": family,
            "location": loc,
            "url": str(job.get("absolute_url") or ""),
            "lookingFor": strip_html(str(job.get("content") or ""), limit=None),
            "companyBrief": f"{company['name']} opening listed on their Greenhouse board.",
            "postedAt": posted,
        }
        attach_optional(row, "segment", classify_segment(title, department=dept))
        attach_optional(row, "workplace", classify_workplace(loc))
        jobs.append(row)
    return jobs, ("ok" if jobs else "zero")


def lever_jobs(company: dict) -> tuple[list[dict], str]:
    payload, health = fetch_json(f"https://api.lever.co/v0/postings/{company['board']}?mode=json")
    jobs = []
    if health == "404":
        return jobs, "404"
    if not isinstance(payload, list):
        return jobs, health if health != "ok" else "error"
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
        workplace_raw = str(job.get("workplaceType") or cats.get("commitment") or "").lower()
        flags = {
            "remote": "remote" in workplace_raw,
            "hybrid": "hybrid" in workplace_raw,
            "onsite": "on-site" in workplace_raw or "onsite" in workplace_raw,
        }
        team = str(cats.get("team") or cats.get("department") or "")
        row = {
            "id": f"{slug(company['name'])}-{slug(title)}-{jid[:12]}",
            "company": company["name"],
            "role": title.strip(),
            "roleFamily": family,
            "location": loc,
            "url": str(job.get("hostedUrl") or job.get("applyUrl") or ""),
            "lookingFor": strip_html(str(job.get("descriptionPlain") or ""), limit=None),
            "companyBrief": f"{company['name']} opening listed on their Lever board.",
            "postedAt": posted,
        }
        attach_optional(row, "segment", classify_segment(title, team=team, department=team))
        attach_optional(row, "workplace", classify_workplace(loc, flags))
        attach_optional(row, "comp", compensation_from_range(job.get("salaryRange") or job.get("salary_range")))
        jobs.append(row)
    return jobs, ("ok" if jobs else "zero")


def ashby_jobs(company: dict) -> tuple[list[dict], str]:
    payload, health = fetch_json(
        f"https://api.ashbyhq.com/posting-api/job-board/{company['board']}"
    )
    jobs = []
    if health == "404":
        return jobs, "404"
    listings = []
    if isinstance(payload, dict):
        listings = payload.get("jobs") or payload.get("jobPostings") or []
    if not isinstance(listings, list):
        return jobs, health if health != "ok" else "error"
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
        workplace_raw = str(job.get("workplaceType") or job.get("employmentType") or "").lower()
        flags = {
            "remote": bool(job.get("isRemote")) or "remote" in workplace_raw,
            "hybrid": "hybrid" in workplace_raw,
            "onsite": "on-site" in workplace_raw or "onsite" in workplace_raw,
        }
        team = str(job.get("teamName") or job.get("departmentName") or job.get("department") or "")
        row = {
            "id": f"{slug(company['name'])}-{slug(title)}-{slug(jid)[:16]}",
            "company": company["name"],
            "role": title.strip(),
            "roleFamily": family,
            "location": loc,
            "url": url,
            "lookingFor": strip_html(
                str(job.get("descriptionPlain") or job.get("descriptionHtml") or ""),
                limit=None,
            ),
            "companyBrief": f"{company['name']} opening listed on their Ashby board.",
            "postedAt": posted,
        }
        attach_optional(row, "segment", classify_segment(title, team=team, department=team))
        attach_optional(row, "workplace", classify_workplace(loc, flags))
        comp = compensation_from_range(
            job.get("compensationMini") or job.get("compensationTier") or job.get("compensationRange")
        )
        if comp is None:
            text = str(job.get("compensationTierSummary") or job.get("compensation") or "").strip()
            if text and "@" not in text and not PHONE_RE.search(text):
                comp = {"text": text[:80]}
        attach_optional(row, "comp", comp)
        jobs.append(row)
    return jobs, ("ok" if jobs else "zero")


FETCHERS = {
    "greenhouse": greenhouse_jobs,
    "lever": lever_jobs,
    "ashby": ashby_jobs,
}


def load_roster(path: Path) -> dict:
    if not path.exists():
        return {}
    data = json.loads(path.read_text())
    return data if isinstance(data, dict) else {}


def build(companies: list[dict], roster: dict, previous: dict) -> dict:
    openings: list[dict] = []
    seen: set[str] = set()
    for company in companies:
        ats = company.get("ats")
        fetcher = FETCHERS.get(ats)
        if not fetcher:
            print(f"skip {company.get('name')}: unknown ats {ats}", file=sys.stderr)
            continue
        try:
            jobs, health = fetcher(company)
        except Exception as exc:  # noqa: BLE001
            print(f"fail {company.get('name')}: {exc}", file=sys.stderr)
            jobs, health = [], "error"
        name = company["name"]
        if health == "404":
            print(f"board health {name}: token 404", file=sys.stderr)
        elif health == "zero":
            print(f"board health {name}: zero jobs", file=sys.stderr)
        elif health != "ok":
            print(f"board health {name}: {health}", file=sys.stderr)
        else:
            print(f"{name} ({ats}): {len(jobs)} sales roles", file=sys.stderr)
        for job in jobs:
            key = job["id"]
            if key in seen or not job.get("url"):
                continue
            seen.add(key)
            plain = job.get("lookingFor") or ""
            attach_hiring_manager(job, plain, roster)
            attach_extracts(job, plain)
            job["lookingFor"] = strip_html(plain, limit=280)
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
    absent = mark_reposted(openings, previous)
    feed: dict[str, object] = {
        "updatedAt": datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds"),
        "openings": openings,
        "companyCounts": company_counts(openings),
    }
    if absent:
        feed["absent"] = absent
    return feed


def main() -> int:
    parser = argparse.ArgumentParser(description="Build Hiintel SDR/BDR/AE feed.json")
    parser.add_argument("--companies", type=Path, default=COMPANIES_PATH)
    parser.add_argument("--managers", type=Path, default=MANAGERS_PATH)
    parser.add_argument("--out", type=Path, default=ROOT / "feed.json")
    args = parser.parse_args()

    companies = json.loads(args.companies.read_text())
    roster = load_roster(args.managers)
    previous = load_previous(args.out)
    feed = build(companies, roster, previous)
    openings = feed.get("openings") if isinstance(feed.get("openings"), list) else []
    prev_openings = previous.get("openings") if isinstance(previous.get("openings"), list) else []
    if not openings and prev_openings:
        print("skipped empty write", file=sys.stderr)
        return 0
    args.out.write_text(json.dumps(feed, indent=2, ensure_ascii=False) + "\n")
    counts: dict[str, int] = {}
    for job in openings:
        counts[job["roleFamily"]] = counts.get(job["roleFamily"], 0) + 1
    print(
        f"Wrote {len(openings)} openings "
        f"({', '.join(f'{k} {v}' for k, v in sorted(counts.items()))}) -> {args.out}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
