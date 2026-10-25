#!/usr/bin/env python3
"""Collect the raw material for a Periop Signal run, so the scheduled runs do not have to fetch it themselves.

Writes one JSON file with:
  journals      per journal: ISSNs tried, status and number of journal articles Crossref registered in the window
  items         every one of those articles: DOI, title, journal, dates, first author, a "noise" flag for
                corrections/replies/letters, the abstract (Crossref or OpenAlex), PMC/PMID ids and open-access
                status (OpenAlex), and author-stated limitation sentences from PMC full text where it is open
  pmcPending    the same limitation sentences for the posts listed in log/pmc-pending.txt
  societyPages  text snapshots of the society and FDA pages the runs check, with the lines that are new
                since the previous snapshot

Runs in GitHub Actions on a schedule (.github/workflows/enumerate.yml). Standard library only.
"""
import argparse
import datetime as dt
import html
import json
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from html.parser import HTMLParser

UA = "PeriopSignal/1.0 (+https://periopsignal.github.io/PeriopSignal/; research feed enumeration)"

# group, journal, ISSNs (the first is the one the run prompts use; the others are tried and merged as well)
JOURNALS = [
    ("Core anesthesiology", "Anesthesiology", ["0003-3022"]),
    ("Core anesthesiology", "Anesthesia & Analgesia", ["0003-2999"]),
    ("Core anesthesiology", "British Journal of Anaesthesia", ["0007-0912"]),
    ("Core anesthesiology", "Anaesthesia", ["0003-2409"]),
    ("Core anesthesiology", "European Journal of Anaesthesiology", ["0265-0215"]),
    ("Core anesthesiology", "Canadian Journal of Anesthesia", ["0832-610X"]),
    ("Core anesthesiology", "Journal of Clinical Anesthesia", ["0952-8180"]),
    ("Cardiothoracic", "J Cardiothorac Vasc Anesth (JCVA)", ["1053-0770"]),
    ("Cardiothoracic", "Seminars in Cardiothoracic and Vascular Anesthesia", ["1089-2532"]),
    ("Cardiothoracic", "JTCVS", ["0022-5223"]),
    ("Cardiothoracic", "JTCVS Open", ["2666-2736"]),
    ("Cardiothoracic", "Annals of Thoracic Surgery", ["0003-4975"]),
    ("Cardiothoracic", "European Journal of Cardio-Thoracic Surgery", ["1010-7940"]),
    ("Cardiothoracic", "Perfusion", ["0267-6591"]),
    ("Cardiology", "Circulation", ["0009-7322"]),
    ("Cardiology", "JACC", ["0735-1097"]),
    ("Cardiology", "JACC: Cardiovascular Interventions", ["1936-8798"]),
    ("Cardiology", "European Heart Journal", ["0195-668X"]),
    ("MCS, heart failure, transplant", "J Heart Lung Transplant", ["1053-2498"]),
    ("MCS, heart failure, transplant", "ASAIO Journal", ["1058-2916"]),
    ("MCS, heart failure, transplant", "Circulation: Heart Failure", ["1941-3289"]),
    ("MCS, heart failure, transplant", "JACC: Heart Failure", ["2213-1779"]),
    ("MCS, heart failure, transplant", "European Journal of Heart Failure", ["1388-9842"]),
    ("MCS, heart failure, transplant", "American Journal of Transplantation", ["1600-6135", "1600-6143"]),
    ("MCS, heart failure, transplant", "Transplantation", ["0041-1337"]),
    ("Echocardiography", "J Am Soc Echocardiogr", ["0894-7317", "1097-6795"]),
    ("Echocardiography", "EHJ Cardiovascular Imaging", ["2047-2404"]),
    ("Echocardiography", "JACC: Cardiovascular Imaging", ["1936-878X"]),
    ("Regional, obstetric, pediatric", "Regional Anesthesia & Pain Medicine", ["1098-7339"]),
    ("Regional, obstetric, pediatric", "Int J Obstetric Anesthesia", ["0959-289X"]),
    ("Regional, obstetric, pediatric", "Pediatric Anesthesia", ["1155-5645"]),
    ("Regional, obstetric, pediatric", "Obstetrics & Gynecology", ["0029-7844"]),
    ("Regional, obstetric, pediatric", "AJOG", ["0002-9378"]),
    ("Regional, obstetric, pediatric", "JAMA Pediatrics", ["2168-6203"]),
    ("Regional, obstetric, pediatric", "Pediatrics", ["0031-4005"]),
    ("Regional, obstetric, pediatric", "Pediatric Critical Care Medicine", ["1529-7535"]),
    ("Thoracic and liver", "Journal of Thoracic Disease", ["2072-1439"]),
    ("Thoracic and liver", "Chest", ["0012-3692"]),
    ("Thoracic and liver", "Liver Transplantation", ["1527-6465"]),
    ("Thoracic and liver", "Hepatology", ["0270-9139"]),
    ("Critical care", "Intensive Care Medicine", ["0342-4642"]),
    ("Critical care", "Critical Care Medicine", ["0090-3493"]),
    ("Critical care", "AJRCCM", ["1073-449X"]),
    ("Critical care", "Critical Care", ["1364-8535"]),
    ("Critical care", "Lancet Respiratory Medicine", ["2213-2600"]),
    ("Critical care", "Resuscitation", ["0300-9572"]),
    ("General medicine and surgery", "NEJM", ["0028-4793"]),
    ("General medicine and surgery", "JAMA", ["0098-7484"]),
    ("General medicine and surgery", "Lancet", ["0140-6736"]),
    ("General medicine and surgery", "BMJ", ["0959-8138", "1756-1833"]),
    ("General medicine and surgery", "JAMA Surgery", ["2168-6254"]),
    ("General medicine and surgery", "Annals of Surgery", ["0003-4932"]),
    ("General medicine and surgery", "J Trauma Acute Care Surg", ["2163-0755"]),
]

SOCIETY_PAGES = {
    "sca_guidelines": "https://scahq.org/practice-resources/clinical-practice-guidelines/",
    "sca_publications": "https://scahq.org/education/publications/",
    "asa_standards": "https://www.asahq.org/standards-and-practice-parameters",
    "ase_guidelines": "https://www.asecho.org/guidelines",
    "sts_guidelines": "https://www.sts.org/resources/clinical-decision-making/clinical-practice-documents-and-policies",
    "elso_guidelines": "https://www.elso.org/ecmo-resources/elso-ecmo-guidelines.aspx",
    "apsf_newsletter": "https://www.apsf.org/apsf-newsletter/",
    "fda_device_recalls": "https://www.fda.gov/medical-devices/medical-device-safety/medical-device-recalls",
}

NOISE = re.compile(
    r"^\s*(correction|corrigendum|corrigenda|erratum|errata|retraction|retracted|notice of retraction|expression of concern|"
    r"withdrawal|withdrawn|reply|in reply|author(s)?['’]? reply|response to|response from|comment on|letter to the editor|"
    r"re:|in this issue|issue highlights|editorial board|masthead|table of contents|cover image|front matter|back matter)(?=\W|$)",
    re.I,
)
TAG = re.compile(r"<[^>]+>")
WS = re.compile(r"\s+")


def log(msg):
    print(msg, file=sys.stderr, flush=True)


def get(url, accept="application/json", tries=4, timeout=60, pause=1.0):
    """GET with retries on 429/5xx and network errors. Returns (status, bytes)."""
    last = (0, b"")
    for attempt in range(tries):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": accept})
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                body = resp.read()
                time.sleep(pause)
                return resp.status, body
        except urllib.error.HTTPError as e:
            try:
                body = e.read()
            except Exception:
                body = b""
            last = (e.code, body)
            if e.code in (429, 500, 502, 503, 504) and attempt < tries - 1:
                time.sleep(6 * (attempt + 1))
                continue
            return last
        except Exception as e:  # timeouts, resets, DNS
            last = (0, str(e).encode())
            if attempt < tries - 1:
                time.sleep(6 * (attempt + 1))
                continue
    return last


def clean(text):
    return WS.sub(" ", html.unescape(TAG.sub(" ", text or ""))).strip()


def date_of(parts_holder):
    try:
        parts = parts_holder["date-parts"][0]
        return "-".join(f"{int(p):02d}" if i else str(int(p)) for i, p in enumerate(parts))
    except Exception:
        return ""


def crossref_items(issn, start):
    params = {
        "filter": f"from-created-date:{start},type:journal-article",
        "rows": "1000",
        "sort": "created",
        "order": "desc",
        "select": "DOI,title,created,published-online,published-print,container-title,author,abstract,type",
    }
    url = f"https://api.crossref.org/journals/{issn}/works?" + urllib.parse.urlencode(params)
    status, body = get(url)
    if status != 200:
        return None, f"HTTP {status}"
    try:
        msg = json.loads(body)["message"]
        return msg.get("items", []), "ok"
    except Exception as e:
        return None, f"bad JSON: {e}"


def to_item(raw, group, journal):
    title = clean((raw.get("title") or [""])[0])
    authors = raw.get("author") or []
    first = ""
    if authors:
        first = authors[0].get("family") or authors[0].get("name") or ""
    published = date_of(raw.get("published-online") or {}) or date_of(raw.get("published-print") or {})
    abstract = clean(raw.get("abstract", ""))
    abstract = re.sub(r"^(abstract|summary)\s*[:.]?\s*", "", abstract, flags=re.I)
    return {
        "doi": raw.get("DOI", "").lower(),
        "title": title,
        "journal": journal,
        "group": group,
        "containerTitle": clean((raw.get("container-title") or [""])[0]),
        "created": date_of(raw.get("created") or {}),
        "published": published,
        "firstAuthor": first,
        "noise": bool(NOISE.search(title)) or not title,
        "abstract": abstract,
        "abstractSource": "crossref" if abstract else "",
        "pmid": "",
        "pmcid": "",
        "oa": None,
        "oaUrl": "",
        "limitations": "",
    }


def openalex_enrich(items):
    """Add abstracts, PMID/PMC ids and open-access status from OpenAlex, 50 DOIs per request."""
    by_doi = {it["doi"]: it for it in items if it["doi"]}
    dois = list(by_doi)
    ok = 0
    for i in range(0, len(dois), 50):
        chunk = dois[i:i + 50]
        params = {
            "filter": "doi:" + "|".join(chunk),
            "per-page": "50",
            "select": "doi,ids,abstract_inverted_index,open_access",
        }
        status, body = get("https://api.openalex.org/works?" + urllib.parse.urlencode(params), pause=0.3)
        if status != 200:
            log(f"OpenAlex chunk {i}: HTTP {status}")
            continue
        try:
            results = json.loads(body).get("results", [])
        except Exception:
            continue
        for w in results:
            doi = (w.get("doi") or "").lower().replace("https://doi.org/", "")
            it = by_doi.get(doi)
            if not it:
                continue
            ok += 1
            ids = w.get("ids") or {}
            it["pmid"] = (ids.get("pmid") or "").rsplit("/", 1)[-1]
            pmc = (ids.get("pmcid") or "").rstrip("/").rsplit("/", 1)[-1]
            it["pmcid"] = pmc if pmc.upper().startswith("PMC") else (f"PMC{pmc}" if pmc else "")
            oa = w.get("open_access") or {}
            it["oa"] = oa.get("is_oa")
            it["oaUrl"] = oa.get("oa_url") or ""
            inv = w.get("abstract_inverted_index")
            if inv and not it["abstract"]:
                words = sorted((pos, word) for word, positions in inv.items() for pos in positions)
                it["abstract"] = " ".join(word for _, word in words)
                it["abstractSource"] = "openalex"
    return ok


def europepmc_enrich(items):
    """Fill missing abstracts and PMC/PMID ids from Europe PMC (PubMed records arrive within days), 40 DOIs per query."""
    need = [it for it in items if it["doi"] and not it["noise"] and (not it["abstract"] or not it["pmcid"])]
    found = 0
    for i in range(0, len(need), 40):
        chunk = {it["doi"]: it for it in need[i:i + 40]}
        query = " OR ".join(f'DOI:"{doi}"' for doi in chunk)
        params = {"query": query, "format": "json", "resultType": "core", "pageSize": "100"}
        status, body = get("https://www.ebi.ac.uk/europepmc/webservices/rest/search?" + urllib.parse.urlencode(params), pause=1.0)
        if status != 200:
            log(f"Europe PMC chunk {i}: HTTP {status}")
            continue
        try:
            results = json.loads(body).get("resultList", {}).get("result", [])
        except Exception:
            continue
        for r in results:
            it = chunk.get((r.get("doi") or "").lower())
            if not it:
                continue
            found += 1
            if not it["abstract"] and r.get("abstractText"):
                it["abstract"] = clean(r["abstractText"])
                it["abstractSource"] = "europepmc"
            if not it["pmcid"] and r.get("pmcid"):
                it["pmcid"] = r["pmcid"]
            if not it["pmid"] and r.get("pmid"):
                it["pmid"] = r["pmid"]
    return found


SENT = re.compile(r"(?<=[.!?])\s+(?=[A-Z(\[])")


def bioc_limitations(identifier):
    """Return (status, text). status: 'full text', 'not available' or 'error: ...'."""
    url = f"https://www.ncbi.nlm.nih.gov/research/bionlp/RESTful/pmcoa.cgi/BioC_json/{identifier}/unicode"
    status, body = get(url, pause=0.4)
    text = body.decode("utf-8", "replace") if body else ""
    if status != 200 or text.lstrip().startswith("[Error]"):
        return ("not available" if (status in (200, 404) or "No result" in text) else f"error: HTTP {status}"), ""
    try:
        data = json.loads(text)
    except Exception:
        return "error: bad JSON", ""
    collections = data if isinstance(data, list) else [data]
    passages = []
    for coll in collections:
        for doc in coll.get("documents", []):
            passages.extend(doc.get("passages", []))
    if not passages:
        return "not available", ""
    body_kinds = {"DISCUSS", "CONCL"}
    chosen = [p for p in passages if (p.get("infons") or {}).get("section_type") in body_kinds
              and (p.get("infons") or {}).get("type", "paragraph") == "paragraph"]
    if not chosen:
        chosen = [p for p in passages if (p.get("infons") or {}).get("type", "paragraph") == "paragraph"]
    sentences = []
    for p in chosen:
        sentences.extend(s.strip() for s in SENT.split(p.get("text", "")) if s.strip())
    picked, i = [], 0
    while i < len(sentences):
        if re.search(r"limitation", sentences[i], re.I):
            picked.extend(sentences[i:i + 5])
            i += 5
        else:
            i += 1
    out, seen = [], set()
    for s in picked:
        if s not in seen:
            seen.add(s)
            out.append(s)
    return "full text", " ".join(out)[:3000]


class TextGrabber(HTMLParser):
    BLOCK = {"p", "div", "li", "tr", "br", "h1", "h2", "h3", "h4", "h5", "h6", "section", "article", "td", "dt", "dd", "header", "footer"}

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.parts, self.skip = [], 0

    def handle_starttag(self, tag, attrs):
        if tag in ("script", "style", "noscript", "svg"):
            self.skip += 1
        elif tag in self.BLOCK:
            self.parts.append("\n")

    def handle_endtag(self, tag):
        if tag in ("script", "style", "noscript", "svg") and self.skip:
            self.skip -= 1
        elif tag in self.BLOCK:
            self.parts.append("\n")

    def handle_data(self, data):
        if not self.skip:
            self.parts.append(data)


def page_text(raw_html):
    g = TextGrabber()
    try:
        g.feed(raw_html)
    except Exception:
        pass
    lines, prev = [], None
    for line in "".join(g.parts).splitlines():
        line = WS.sub(" ", line).strip()
        if line and line != prev:
            lines.append(line)
            prev = line
    return lines


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--days", type=int, default=21)
    ap.add_argument("--out", required=True)
    ap.add_argument("--previous", help="previous data.json, for the new-lines diff of society pages")
    ap.add_argument("--pending", help="log/pmc-pending.txt")
    args = ap.parse_args()

    now = dt.datetime.now(dt.timezone.utc)
    start = (now - dt.timedelta(days=args.days)).date().isoformat()
    previous = {}
    if args.previous:
        try:
            previous = json.load(open(args.previous, encoding="utf-8"))
        except Exception:
            previous = {}

    out = {
        "generatedAt": now.isoformat(timespec="seconds").replace("+00:00", "Z"),
        "days": args.days,
        "windowStart": start,
        "journals": [],
        "items": [],
        "pmcPending": {},
        "societyPages": {},
        "notes": [],
    }

    # 1. Crossref, journal by journal
    seen = set()
    for group, journal, issns in JOURNALS:
        count, statuses = 0, []
        for issn in issns:
            raw_items, status = crossref_items(issn, start)
            statuses.append(f"{issn}: {status}")
            if raw_items is None:
                continue
            for raw in raw_items:
                it = to_item(raw, group, journal)
                if it["doi"] and it["doi"] not in seen:
                    seen.add(it["doi"])
                    out["items"].append(it)
                    count += 1
        ok = any(s.endswith(": ok") for s in statuses)
        out["journals"].append({"group": group, "journal": journal, "issns": issns, "status": "ok" if ok else "failed",
                                "detail": "; ".join(statuses), "count": count})
        log(f"{journal}: {count} ({'; '.join(statuses)})")

    # 2. OpenAlex abstracts and ids
    matched = openalex_enrich(out["items"])
    out["notes"].append(f"OpenAlex matched {matched} of {len(out['items'])} DOIs")
    epmc = europepmc_enrich(out["items"])
    out["notes"].append(f"Europe PMC matched {epmc} of the DOIs that still lacked an abstract or PMC id")

    # 3. PMC limitations for open full texts among the items (most new papers have none yet)
    for it in out["items"]:
        if it["pmcid"] and not it["noise"]:
            status, text = bioc_limitations(it["pmcid"])
            if status == "full text":
                it["limitations"] = text
                it["fullText"] = True

    # 4. PMC limitations for posts waiting on embargoed full text
    if args.pending:
        try:
            lines = open(args.pending, encoding="utf-8").read().splitlines()
        except Exception:
            lines = []
        for line in lines:
            if not line.strip() or line.lstrip().startswith("#"):
                continue
            parts = [p.strip() for p in line.split("|")]
            if len(parts) < 2 or not parts[1]:
                continue
            post_id, ident = parts[0], parts[1]
            note = parts[2] if len(parts) > 2 else ""
            if "fetch cap" in note:
                continue
            status, text = bioc_limitations(ident)
            out["pmcPending"][post_id] = {"id": ident, "status": status, "limitations": text}

    # 5. Society and FDA pages
    prev_pages = previous.get("societyPages", {}) if isinstance(previous, dict) else {}
    for key, url in SOCIETY_PAGES.items():
        status, body = get(url, accept="text/html,application/xhtml+xml", pause=0.5)
        entry = {"url": url, "status": status, "text": "", "newLines": []}
        if status == 200 and body:
            lines = page_text(body.decode("utf-8", "replace"))
            text = "\n".join(lines)
            entry["text"] = text[:20000]
            old = set((prev_pages.get(key) or {}).get("text", "").splitlines())
            if old:
                entry["newLines"] = [l for l in lines if len(l) >= 20 and l not in old][:80]
            else:
                entry["newLines"] = ["(no previous snapshot to compare with)"]
        out["societyPages"][key] = entry
        log(f"{key}: HTTP {status}")

    out["notes"].append(f"{len(out['items'])} items, {sum(1 for i in out['items'] if not i['noise'])} not flagged as noise, "
                        f"{sum(1 for i in out['items'] if i['abstract'])} with abstracts")
    with open(args.out, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, indent=1)
    log("; ".join(out["notes"]))


if __name__ == "__main__":
    main()
