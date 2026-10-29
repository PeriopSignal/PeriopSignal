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

    inf = data.get("infusions")
    if inf is not None:
        groups = inf.get("groups")
        need(isinstance(groups, list) and groups, "infusions.groups must be a non-empty list")
        seen = set()
        forms = {"perKgPerMin", "perMin", "perKg", "perKgPerHour", "perHour", "fixed", "text"}
        for g in groups or []:
            need(isinstance(g.get("name"), str) and g["name"], "infusion group needs a name")
            if g.get("tab") is not None:
                need(isinstance(g["tab"], str) and g["tab"].strip(), f"infusion group {g.get('name')}: tab must be text")
            names = [d.get("name", "") for d in g.get("drugs") or []]
            need(names == sorted(names, key=str.lower), f"infusion group {g.get('name')}: drugs must be alphabetical")
            for d in g.get("drugs") or []:
                did = d.get("id", "?")
                need(did not in seen, f"infusion {did}: duplicate id"); seen.add(did)
                for key in ("name", "use", "form", "source"):
                    need(isinstance(d.get(key), str) and d[key].strip(), f"infusion {did}: {key} required")
                need(d.get("form") in forms, f"infusion {did}: form must be one of {sorted(forms)}")
                if d.get("form") == "text":
                    need(isinstance(d.get("display"), str), f"infusion {did}: text rows need a short display dose")
                if d.get("form") not in ("text",):
                    need(isinstance(d.get("start"), (int, float)) and d["start"] > 0, f"infusion {did}: start must be > 0")
                    need(isinstance(d.get("unit"), str) and d["unit"], f"infusion {did}: unit required")
                if d.get("startHigh") is not None:
                    need(isinstance(d["startHigh"], (int, float)) and d["startHigh"] >= (d.get("start") or 0), f"infusion {did}: startHigh >= start")
                for key in ("role", "threshold", "display"):
                    if d.get(key) is not None:
                        need(isinstance(d[key], str) and d[key].strip(), f"infusion {did}: {key} must be non-empty text")
            if g.get("name") == "Blood Products":
                for d in g.get("drugs") or []:
                    need(isinstance(d.get("threshold"), str), f"blood product {d.get('id')}: threshold required (shown on the row)")

    nx = data.get("neuraxial")
    if nx is not None:
        need(isinstance(nx.get("source"), str) and nx["source"], "neuraxial.source required")
        need(isinstance(nx.get("general"), list), "neuraxial.general must be a list")
        seen = set()
        for g in nx.get("groups") or []:
            for d in g.get("drugs") or []:
                did = d.get("id", "?")
                need(did not in seen, f"neuraxial {did}: duplicate id"); seen.add(did)
                tiers = d.get("tiers")
                need(isinstance(tiers, list) and tiers, f"neuraxial {did}: tiers required")
                for t in tiers or []:
                    need(isinstance(t.get("id"), str) and isinstance(t.get("label"), str), f"neuraxial {did}: tier id/label required")
                    for key in ("holdHours", "restartHours", "removalHours", "afterRemovalHours"):
                        if t.get(key) is not None:
                            need(isinstance(t[key], (int, float)) and t[key] >= 0, f"neuraxial {did}/{t.get('id')}: {key} must be a number >= 0")
                    for r in t.get("renal") or []:
                        need(isinstance(r.get("label"), str), f"neuraxial {did}/{t.get('id')}: renal rule label")
                        if r.get("hours") is None:
                            need(isinstance(r.get("text"), str), f"neuraxial {did}/{t.get('id')}: renal rule without hours needs text")

    ponv = data.get("ponv")
    if ponv is not None:
        need(isinstance(ponv.get("source"), str) and ponv["source"], "ponv.source required")
        counts = ponv.get("counts") or []
        need(counts and all(isinstance(c.get("agents"), int) and c["agents"] > 0 for c in counts), "ponv.counts need agents > 0")
        covered = sorted(n for c in counts for n in range(c.get("minFactors", 0), c.get("maxFactors", -1) + 1))
        need(covered == [0, 1, 2, 3, 4], "ponv.counts must cover 0–4 Apfel factors exactly once")
        seen = set()
        for a in ponv.get("agents") or []:
            aid = a.get("id", "?")
            need(aid not in seen, f"ponv agent {aid}: duplicate id"); seen.add(aid)
            for key in ("name", "class", "dose"):
                need(isinstance(a.get(key), str) and a[key].strip(), f"ponv agent {aid}: {key} required")
        need(any(a.get("rescue") for a in ponv.get("agents") or []), "ponv: at least one rescue agent")
        need(isinstance(ponv.get("rescueRules"), list) and ponv["rescueRules"], "ponv.rescueRules required")

    echo = data.get("echo")
    if echo is not None:
        need(echo.get("bsaFormula") in (None, "dubois", "mosteller"), "echo.bsaFormula must be dubois or mosteller")
        src_ids = {s.get("id") for s in echo.get("sources") or []}
        for s_ in echo.get("sources") or []:
            need(isinstance(s_.get("citation"), str) and s_["citation"].strip(), f"echo source {s_.get('id')}: citation required")
            need(s_.get("url") is None or str(s_["url"]).startswith("https://"), f"echo source {s_.get('id')}: url must be https")

        def check_refs(mid, holder, low, label):
            """Reference sets and edges of a row (or of its indexed cutoffs)."""
            refs_ = [holder.get(k) for k in ("male", "female", "all") if holder.get(k) is not None]
            need(refs_, f"echo measure {mid}: {label} needs male/female or all reference values")
            edges = holder.get("edges")
            need(holder.get("edge") in (None, "inclusive"), f"echo measure {mid}: {label} edge must be inclusive")
            need(edges is None or (isinstance(edges, list) and all(e in ("inclusive", "exclusive") for e in edges)), f"echo measure {mid}: {label} edges must be inclusive or exclusive")
            for r in refs_:
                cuts = r.get("cuts") or []
                need(len(cuts) in (1, 3) and all(isinstance(c, (int, float)) for c in cuts), f"echo measure {mid}: {label} cuts must be 1 or 3 numbers")
                need(cuts == sorted(cuts, reverse=low), f"echo measure {mid}: {label} cuts must run from normal towards severe")
                need(edges is None or len(edges) == len(cuts), f"echo measure {mid}: {label} needs one edge per cut")
                n = r.get("normal")
                if n is not None:
                    need(isinstance(n, list) and len(n) == 2 and n[0] < n[1], f"echo measure {mid}: {label} normal must be [low, high]")
                    if n and len(n) == 2 and cuts:
                        need((n[1] <= cuts[0] + 1e-9) if not low else (n[0] >= cuts[0] - 1e-9), f"echo measure {mid}: {label} first cut must sit at the edge of the normal range")

        gids, mids = set(), set()
        for g in echo.get("groups") or []:
            gid = g.get("id", "?")
            need(gid not in gids, f"echo group {gid}: duplicate id"); gids.add(gid)
            need(isinstance(g.get("name"), str) and g["name"], f"echo group {gid}: name required")
            need(g.get("measures"), f"echo group {gid}: measures required")
            for m in g.get("measures") or []:
                mid = m.get("id", "?")
                need(mid not in mids, f"echo measure {mid}: duplicate id"); mids.add(mid)
                need(isinstance(m.get("name"), str) and m["name"].strip(), f"echo measure {mid}: name required")
                need(isinstance(m.get("unit"), str), f"echo measure {mid}: unit required (empty for a ratio)")
                need(m.get("dir") in (None, "high", "low"), f"echo measure {mid}: dir must be high or low")
                need(m.get("index") in (None, "bsa"), f"echo measure {mid}: index must be bsa")
                need(m.get("index") != "bsa" or isinstance(m.get("rawUnit"), str), f"echo measure {mid}: an indexed row needs rawUnit")
                need(m.get("abs") in (None, True), f"echo measure {mid}: abs must be true when present")
                need(m.get("source") in src_ids, f"echo measure {mid}: source must name an echo source")
                low = m.get("dir") == "low"
                by_age = m.get("byAge")
                if by_age is not None:
                    need(isinstance(by_age.get("perM2"), (int, float)), f"echo measure {mid}: byAge.perM2 required")
                    for sx in ("male", "female"):
                        t = by_age.get(sx) or {}
                        need(isinstance(t.get("refBsa"), (int, float)) and t["refBsa"] > 0, f"echo measure {mid}: byAge.{sx}.refBsa required")
                        rows = t.get("rows") or []
                        need(rows, f"echo measure {mid}: byAge.{sx}.rows required")
                        for i, row in enumerate(rows):
                            need(isinstance(row.get("from"), int) and isinstance(row.get("uln"), (int, float)), f"echo measure {mid}: byAge.{sx} row needs from and uln")
                            last = i == len(rows) - 1
                            need((row.get("to") is None) == last, f"echo measure {mid}: byAge.{sx}: only the last band is open-ended")
                            if i:
                                need(row["from"] == rows[i - 1]["to"] + 1, f"echo measure {mid}: byAge.{sx} bands must be contiguous")
                else:
                    check_refs(mid, m, low, "row")
                if m.get("indexed") is not None:
                    x = m["indexed"]
                    need(isinstance(x.get("unit"), str) and x["unit"].endswith("/m²"), f"echo measure {mid}: indexed.unit must be per m²")
                    need(m.get("index") is None, f"echo measure {mid}: a row is either indexed or carries indexed cutoffs")
                    check_refs(mid, x, low, "indexed")
        ivc = echo.get("ivc")
        if ivc is not None:
            need(ivc.get("group") in gids, "echo.ivc.group must name an echo group")

    dia = data.get("diastolic")
    if dia is not None:
        src = dia.get("source") or {}
        need(isinstance(src.get("citation"), str) and src["citation"], "diastolic.source.citation required")
        need(isinstance(src.get("url"), str) and src["url"].startswith("https://"), "diastolic.source.url must be https")
        need(isinstance(dia.get("scope"), str) and dia["scope"], "diastolic.scope required")
        pops = dia.get("populations") or []
        need(pops and pops[0].get("mode") == "main", "diastolic.populations must start with the main algorithm")
        seen = set()
        for pop in pops:
            pid = pop.get("id", "?")
            need(pid not in seen, f"diastolic population {pid}: duplicate id"); seen.add(pid)
            need(pop.get("mode") in ("main", "mac", "transplant", "list"), f"diastolic population {pid}: mode must be main, mac, transplant or list")
            need(isinstance(pop.get("name"), str) and pop["name"], f"diastolic population {pid}: name required")
            if pop.get("mode") == "list":
                need(pop.get("indicators") or pop.get("notes"), f"diastolic population {pid}: a list population needs indicators or notes")
        for row in dia.get("exercise") or []:
            need(isinstance(row, list) and len(row) == 2, "diastolic.exercise rows are [label, text]")

    if problems:
        print("\n".join("- " + p for p in problems))
        print(f"FAILED: {len(problems)} problem(s)")
        return 1
    n_sections = sum(len(r["sections"]) for r in refs)
    n_inf = sum(len(g.get("drugs") or []) for g in (inf or {}).get("groups") or [])
    print(f"OK: {len(refs)} quick references, {n_sections} sections; {len((peds or {}).get('drugs') or [])} pediatric drugs; {n_inf} infusion rows")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else "reference.json"))
