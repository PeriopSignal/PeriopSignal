#!/usr/bin/env python3
"""Fill in `title` and `citation` for posts that link to a DOI, from Crossref.

    python3 -I tools/backfill_citations.py [posts.json] [--all]

Only posts without a citation are looked up (all DOI posts with --all). Exit code 0 whether or not
anything changed; prints a one-line summary. Runs in GitHub Actions (.github/workflows/citations.yml),
where Crossref is reachable; the scheduled feed runs cannot call it directly.
"""
import json
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

UA = "PeriopSignal/1.0 (+https://periopsignal.github.io/PeriopSignal/; mailto:periopsignal@users.noreply.github.com)"
TAG = re.compile(r"<[^>]+>")
WS = re.compile(r"\s+")


def clean(s):
    return WS.sub(" ", TAG.sub("", s or "")).strip()


def doi_of(url):
    m = re.search(r"doi\.org/(10\.\S+)$", url.strip(), re.I)
    return urllib.parse.unquote(m.group(1)).rstrip("/.") if m else None


def fetch(doi):
    req = urllib.request.Request("https://api.crossref.org/works/" + urllib.parse.quote(doi, safe="/()"),
                                 headers={"User-Agent": UA, "Accept": "application/json"})
    for attempt in range(3):
        try:
            with urllib.request.urlopen(req, timeout=40) as r:
                return json.loads(r.read())["message"]
        except urllib.error.HTTPError as e:
            if e.code == 404:
                return None
            if attempt == 2:
                return None
            time.sleep(5 * (attempt + 1))
        except Exception:
            if attempt == 2:
                return None
            time.sleep(5 * (attempt + 1))
    return None


def initials(given):
    parts = re.split(r"[\s.\-]+", given or "")
    return "".join(p[0].upper() for p in parts if p)


def record(m, doi):
    authors = []
    for a in m.get("author", []) or []:
        if a.get("family"):
            authors.append((a["family"] + " " + initials(a.get("given"))).strip())
        elif a.get("name"):
            authors.append(a["name"])
    title = clean((m.get("title") or [""])[0])
    journal = clean((m.get("short-container-title") or m.get("container-title") or [""])[0])
    year = None
    for key in ("published-print", "published-online", "issued", "created"):
        parts = (m.get(key) or {}).get("date-parts") or [[None]]
        if parts and parts[0] and parts[0][0]:
            year = int(parts[0][0])
            break
    cit = {"title": title, "authors": authors[:12], "journal": journal, "doi": doi}
    if year:
        cit["year"] = year
    for src, dst in (("volume", "volume"), ("issue", "issue"), ("page", "pages")):
        v = m.get(src)
        if isinstance(v, str) and v.strip():
            cit[dst] = v.strip()
    return cit


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    path = args[0] if args else "posts.json"
    force = "--all" in sys.argv
    data = json.load(open(path, encoding="utf-8"))
    looked, filled, missing = 0, 0, []
    for p in data["posts"]:
        doi = doi_of(p.get("url", ""))
        if not doi or (p.get("citation") and not force):
            continue
        looked += 1
        m = fetch(doi)
        time.sleep(0.6)
        if not m:
            missing.append(p["id"])
            continue
        cit = record(m, doi)
        if not cit["title"]:
            missing.append(p["id"])
            continue
        p["citation"] = cit
        p["title"] = cit["title"]
        filled += 1
    if filled:
        json.dump(data, open(path, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print(f"looked up {looked}, filled {filled}, not found {len(missing)}" + (": " + ", ".join(missing[:10]) if missing else ""))


if __name__ == "__main__":
    main()
