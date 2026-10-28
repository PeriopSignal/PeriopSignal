#!/usr/bin/env python3
"""Validate reference.json (the app's Reference tab content) against the shape the app decodes.

Usage: python3 -I tools/validate_reference.py reference.json
Exit code 1 and a list of problems when something is off; "OK: ..." otherwise.
"""
import json, re, sys

SECTION_KINDS = {"table", "list", "steps", "text", "facts"}
DATE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
UNITS = {"mg", "mcg", "g", "mL", "mEq", "J", "units", "mmol"}


def main(path):
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    problems = []

    def need(cond, msg):
        if not cond:
            problems.append(msg)

    need(isinstance(data.get("version"), int) and data["version"] >= 1, "version must be an integer >= 1")
    need(isinstance(data.get("updated"), str) and DATE.match(data["updated"] or ""), "updated must be YYYY-MM-DD")
    ask = data.get("ask")
    if ask is not None:
        need(isinstance(ask, dict), "ask must be an object")
        ep = (ask or {}).get("endpoint")
        need(ep is None or (isinstance(ep, str) and ep.startswith("https://")), "ask.endpoint must be https")

    refs = data.get("quickrefs")
    need(isinstance(refs, list) and refs, "quickrefs must be a non-empty list")
    ids = set()
    for r in refs or []:
        rid = r.get("id", "?")
        need(re.match(r"^[a-z0-9-]+$", rid or ""), f"{rid}: id must be lowercase letters, digits and dashes")
        need(rid not in ids, f"{rid}: duplicate id")
        ids.add(rid)
        for key in ("title", "society", "summary"):
            need(isinstance(r.get(key), str) and r[key].strip(), f"{rid}: {key} required")
        src = r.get("source") or {}
        need(isinstance(src.get("title"), str) and src["title"], f"{rid}: source.title required")
        need(isinstance(src.get("url"), str) and src["url"].startswith("https://"), f"{rid}: source.url must be https")
        if "year" in r:
            need(isinstance(r["year"], int) and 1990 <= r["year"] <= 2100, f"{rid}: year out of range")
        if "reviewed" in r:
            need(DATE.match(r["reviewed"] or ""), f"{rid}: reviewed must be YYYY-MM-DD")
        if "emergency" in r:
            need(isinstance(r["emergency"], bool), f"{rid}: emergency must be true/false")
        if "keywords" in r:
            need(isinstance(r["keywords"], list) and all(isinstance(k, str) for k in r["keywords"]), f"{rid}: keywords must be strings")
        sections = r.get("sections")
        need(isinstance(sections, list) and sections, f"{rid}: sections must be a non-empty list")
        for i, s in enumerate(sections or []):
            tag = f"{rid} section {i + 1}"
            kind = s.get("kind")
            need(kind in SECTION_KINDS, f"{tag}: kind must be one of {sorted(SECTION_KINDS)}")
            if kind == "table":
                cols = s.get("columns")
                need(isinstance(cols, list) and len(cols) >= 2, f"{tag}: table needs >= 2 columns")
                rows = s.get("rows")
                need(isinstance(rows, list) and rows, f"{tag}: table needs rows")
                for j, row in enumerate(rows or []):
                    need(isinstance(row, list) and all(isinstance(c, str) for c in row), f"{tag} row {j + 1}: cells must be strings")
                    need(isinstance(cols, list) and len(row) == len(cols), f"{tag} row {j + 1}: {len(row)} cells for {len(cols or [])} columns")
            elif kind == "facts":
                rows = s.get("rows")
                need(isinstance(rows, list) and rows, f"{tag}: facts needs rows")
                for j, row in enumerate(rows or []):
                    need(isinstance(row, list) and len(row) == 2 and all(isinstance(c, str) for c in row), f"{tag} row {j + 1}: facts rows are [label, value]")
            elif kind in ("list", "steps"):
                items = s.get("items")
                need(isinstance(items, list) and items and all(isinstance(x, str) and x.strip() for x in items), f"{tag}: items must be non-empty strings")
            elif kind == "text":
                need(isinstance(s.get("text"), str) and s["text"].strip(), f"{tag}: text required")
            if "note" in s:
                need(isinstance(s["note"], str), f"{tag}: note must be a string")

    peds = data.get("peds")
    if peds is not None:
        drugs = peds.get("drugs")
        need(isinstance(drugs, list) and drugs, "peds.drugs must be a non-empty list")
        dids = set()
        for d in drugs or []:
            did = d.get("id", "?")
            need(did not in dids, f"peds drug {did}: duplicate id")
            dids.add(did)
            for key in ("name", "use", "group", "route", "unit"):
                need(isinstance(d.get(key), str) and d[key].strip(), f"peds drug {did}: {key} required")
            need(d.get("unit") in UNITS, f"peds drug {did}: unit must be one of {sorted(UNITS)}")
            low = d.get("low")
            need(isinstance(low, (int, float)) and low > 0, f"peds drug {did}: low must be > 0")
            if d.get("high") is not None:
                need(isinstance(d["high"], (int, float)) and d["high"] >= (low or 0), f"peds drug {did}: high must be >= low")
            if d.get("max") is not None:
                need(isinstance(d["max"], (int, float)) and d["max"] > 0, f"peds drug {did}: max must be > 0")
            if d.get("min") is not None:
                need(isinstance(d["min"], (int, float)) and 0 < d["min"] <= (d.get("max") or float("inf")), f"peds drug {did}: min must be > 0 and <= max")
            need(isinstance(d.get("source"), str) and d["source"].strip(), f"peds drug {did}: source required")
        for la in peds.get("localAnesthetics") or []:
            need(isinstance(la.get("maxMgPerKg"), (int, float)) and la["maxMgPerKg"] > 0, f"local anesthetic {la.get('id')}: maxMgPerKg > 0")
            need(isinstance(la.get("concentrations"), list) and la["concentrations"], f"local anesthetic {la.get('id')}: concentrations required")
        need(isinstance(peds.get("bloodVolume"), list) and peds["bloodVolume"], "peds.bloodVolume required")
        for row in peds.get("bloodVolume") or []:
            need(0 < row.get("mlPerKgLow", 0) <= row.get("mlPerKgHigh", 0), f"blood volume {row.get('group')}: low <= high and > 0")

    if problems:
        print("\n".join("- " + p for p in problems))
        print(f"FAILED: {len(problems)} problem(s)")
        return 1
    n_sections = sum(len(r["sections"]) for r in refs)
    print(f"OK: {len(refs)} quick references, {n_sections} sections; {len((peds or {}).get('drugs') or [])} pediatric drugs")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else "reference.json"))
