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
            for k in ("cut", "ventCut"):
                need(ivc.get(k) is None or (isinstance(ivc[k], (int, float)) and 0 < ivc[k] < 5), f"echo.ivc.{k} must be a diameter in cm")

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

    acls = data.get("acls")
    if acls is not None:
        num = lambda v: isinstance(v, (int, float)) and not isinstance(v, bool)
        need(num(acls.get("cycleSec")) and acls["cycleSec"] > 0, "acls.cycleSec must be a positive number")
        src_ids = set()
        for s_ in acls.get("sources") or []:
            need(isinstance(s_.get("citation"), str) and s_["citation"].strip(), f"acls source {s_.get('id')}: citation required")
            need(s_.get("url") is None or str(s_["url"]).startswith("https://"), f"acls source {s_.get('id')}: url must be https")
            src_ids.add(s_.get("id"))
        actions = acls.get("actions") or {}
        mode_ids = [m.get("id") for m in acls.get("modes") or []]
        need(len(mode_ids) == len(set(mode_ids)), "acls modes: duplicate id")

        def check_spec(aid, who, sp, kind):
            where = f"acls action {aid} ({who})"
            if kind == "shock":
                need(sp.get("text") or sp.get("perKgSeq"), f"{where}: an energy needs text or perKgSeq")
                if sp.get("perKgSeq") is not None:
                    need(all(num(v) and v > 0 for v in sp["perKgSeq"]) and num(sp.get("thenPerKg")), f"{where}: perKgSeq and thenPerKg must be positive numbers")
                    need(sp.get("maxPerKg") is None or (num(sp["maxPerKg"]) and sp["maxPerKg"] >= sp.get("thenPerKg", 0)), f"{where}: maxPerKg must be at least thenPerKg")
                return
            entries = [sp] + list(sp.get("doses") or [])
            for e in entries:
                for k in ("dose", "perKg", "max", "min"):
                    need(e.get(k) is None or (num(e[k]) and e[k] > 0), f"{where}: {k} must be a positive number")
            need(sp.get("dose") is not None or sp.get("perKg") is not None or sp.get("text") or sp.get("doses"), f"{where}: needs dose, perKg, text or doses")
            for e in entries:
                if e.get("dose") is not None or e.get("perKg") is not None:
                    need(isinstance(e.get("unit", sp.get("unit")), str), f"{where}: a numeric dose needs a unit")
            if sp.get("perKg") is not None and sp.get("max") is not None and sp.get("min") is not None:
                need(sp["min"] <= sp["max"], f"{where}: min above max")
            if sp.get("conc") is not None:
                need(num(sp["conc"].get("value")) and sp["conc"]["value"] > 0 and isinstance(sp["conc"].get("unit"), str), f"{where}: conc needs value and unit")
            need(sp.get("maxDoses") is None or (isinstance(sp["maxDoses"], int) and sp["maxDoses"] >= 1), f"{where}: maxDoses must be a whole number of 1 or more")

        for aid, a in actions.items():
            need(isinstance(a.get("label"), str) and a["label"], f"acls action {aid}: label required")
            kind = a.get("kind")
            need(kind in ("drug", "shock", "rhythm", "event"), f"acls action {aid}: kind must be drug, shock, rhythm or event")
            if kind == "rhythm":
                need(a.get("rhythm") in ("shockable", "nonshockable", "rosc"), f"acls action {aid}: rhythm must be shockable, nonshockable or rosc")
            if kind in ("drug", "shock"):
                need(a.get("adult") or a.get("child"), f"acls action {aid}: needs an adult or child spec")
                for who in ("adult", "child"):
                    if a.get(who) is not None:
                        check_spec(aid, who, a[who], kind)
            rep = a.get("repeat")
            if rep is not None:
                need(num(rep.get("min")) and rep["min"] > 0, f"acls action {aid}: repeat.min must be positive")
                need(rep.get("max") is None or (num(rep["max"]) and rep["max"] > rep["min"]), f"acls action {aid}: repeat.max must exceed min")
            if a.get("goto") is not None:
                need(a["goto"] in mode_ids, f"acls action {aid}: goto names no mode")
            for p_ in a.get("patients") or []:
                need(p_ in ("adult", "child"), f"acls action {aid}: patients are adult or child")

        placeholder = re.compile(r"\{(dose|energy|count|next):([a-z0-9-]+)\}")
        ops = (">=", ">", "<=", "<", "==")
        for m in acls.get("modes") or []:
            mid = m.get("id", "?")
            need(isinstance(m.get("name"), str) and m["name"], f"acls mode {mid}: name required")
            for p_ in m.get("patients") or []:
                need(p_ in ("adult", "child"), f"acls mode {mid}: patients are adult or child")
            for sid in m.get("sources") or []:
                need(sid in src_ids, f"acls mode {mid}: source {sid} is not listed")
            for g in m.get("groups") or []:
                need(isinstance(g.get("title"), str) and g["title"], f"acls mode {mid}: group title required")
                for aid in g.get("actions") or []:
                    need(aid in actions, f"acls mode {mid}: group names unknown action {aid}")
            pids = set()
            for p in m.get("prompts") or []:
                pid = p.get("id", "?")
                need(pid not in pids, f"acls mode {mid}: duplicate prompt {pid}"); pids.add(pid)
                need(isinstance(p.get("text"), str) and p["text"], f"acls prompt {mid}/{pid}: text required")
                need(p.get("level", "info") in ("now", "soon", "info"), f"acls prompt {mid}/{pid}: level must be now, soon or info")
                need(p.get("action") is None or p["action"] in actions, f"acls prompt {mid}/{pid}: unknown action")
                for kind, aid in placeholder.findall(p.get("text") or ""):
                    need(aid in actions, f"acls prompt {mid}/{pid}: {{{kind}:{aid}}} names no action")
                for c in p.get("when") or []:
                    keys = set(c)
                    need(keys and keys <= {"patient", "rhythm", "done", "not", "notAny", "count", "countAny", "countSince", "since", "elapsed", "cycle", "weight"}, f"acls prompt {mid}/{pid}: unknown condition {sorted(keys)}")
                    if "countAny" in c:
                        v = c["countAny"]
                        need(isinstance(v, list) and len(v) == 3 and isinstance(v[0], list) and v[0] and all(x in actions for x in v[0]) and v[1] in ops and num(v[2]), f"acls prompt {mid}/{pid}: countAny is [[ids], op, n]")
                    if "count" in c or "since" in c:
                        v = c.get("count") or c.get("since")
                        need(isinstance(v, list) and len(v) == 3 and v[1] in ops and num(v[2]), f"acls prompt {mid}/{pid}: count/since is [id, op, n]")
                    if "countSince" in c:
                        v = c["countSince"]
                        need(isinstance(v, list) and len(v) == 4 and v[2] in ops and num(v[3]), f"acls prompt {mid}/{pid}: countSince is [id, sinceId, op, n]")
                    for k in ("elapsed", "cycle"):
                        if k in c:
                            v = c[k]
                            need(isinstance(v, list) and len(v) == 2 and v[0] in ops and num(v[1]), f"acls prompt {mid}/{pid}: {k} is [op, seconds]")
                    if "rhythm" in c:
                        need(c["rhythm"] in ("shockable", "nonshockable", "rosc"), f"acls prompt {mid}/{pid}: unknown rhythm")
            for dl in m.get("deadlines") or []:
                need(num(dl.get("sec")) and dl["sec"] > 0, f"acls mode {mid}: deadline {dl.get('id')} needs sec")
                need(dl.get("until") is None or dl["until"] in actions, f"acls mode {mid}: deadline {dl.get('id')} until names no action")
            for who, tr in (m.get("tree") or {}).items():
                need(who in ("adult", "child", "all"), f"acls mode {mid}: tree key must be adult, child or all")
                nodes = tr.get("nodes") or {}
                need(tr.get("start") in nodes, f"acls mode {mid}: tree {who} start names no node")
                for nid, n in nodes.items():
                    need(n.get("q") or n.get("text") or n.get("title"), f"acls mode {mid}: node {nid} is empty")
                    if n.get("q"):
                        need(n.get("options"), f"acls mode {mid}: question {nid} needs options")
                    for o in n.get("options") or []:
                        need(o.get("next") in nodes and o.get("label"), f"acls mode {mid}: node {nid} option leads nowhere")
                    for aid in n.get("actions") or []:
                        need(aid in actions, f"acls mode {mid}: node {nid} names unknown action {aid}")
            for l in m.get("lists") or []:
                ids = [x.get("id") for x in l.get("items") or []]
                need(ids and len(ids) == len(set(ids)) and all(isinstance(x.get("label"), str) and x["label"] for x in l["items"]), f"acls mode {mid}: list {l.get('id')} needs unique, labelled items")

    abg = data.get("abg")
    if abg is not None:
        num = lambda v: isinstance(v, (int, float)) and not isinstance(v, bool)
        pair = lambda r: isinstance(r, list) and len(r) == 2 and all(num(x) for x in r) and r[0] < r[1]
        for key in ("normal", "plausible"):
            rng = abg.get(key)
            if key == "plausible" and rng is None:
                continue
            for k in ("ph", "paco2", "hco3"):
                need(isinstance(rng, dict) and pair(rng.get(k)), f"abg.{key}.{k} must be [low, high]")
        mid = abg.get("mid") or {}
        for k in ("ph", "paco2", "hco3"):
            need(num(mid.get(k)) and pair((abg.get("normal") or {}).get(k)) and abg["normal"][k][0] < mid[k] < abg["normal"][k][1], f"abg.mid.{k} must sit inside the normal range")
        chk = abg.get("check") or {}
        need(num(chk.get("pk")) and 5.5 < chk["pk"] < 6.5 and num(chk.get("solubility")) and 0 < chk["solubility"] < 0.1 and num(chk.get("tol")) and 0 < chk["tol"] < 0.2,
             "abg.check needs pk (about 6.1), solubility (about 0.03) and a small pH tolerance")
        rules = abg.get("rules") or {}
        src_ids = {s_.get("id") for s_ in abg.get("sources") or []}
        for s_ in abg.get("sources") or []:
            need(isinstance(s_.get("citation"), str) and s_["citation"].strip(), f"abg source {s_.get('id')}: citation required")
            need(s_.get("url") is None or str(s_["url"]).startswith("https://"), f"abg source {s_.get('id')}: url must be https")
        for rid in ("metAcid", "metAlk", "respAcidAcute", "respAcidChronic", "respAlkAcute", "respAlkChronic"):
            r_ = rules.get(rid)
            need(isinstance(r_, dict) and num(r_.get("slope")) and r_["slope"] > 0 and num(r_.get("intercept")) and (r_.get("tol") is None or (num(r_["tol"]) and r_["tol"] >= 0)),
                 f"abg.rules.{rid} needs a positive slope, an intercept and an optional tolerance")
            if isinstance(r_, dict):
                need(isinstance(r_.get("formula"), str) and r_["formula"].strip(), f"abg.rules.{rid}: formula text required")
                need(r_.get("source") in src_ids, f"abg.rules.{rid}: source must name an abg source")
                need(r_.get("xmax") is None or (num(r_["xmax"]) and r_["xmax"] > 0), f"abg.rules.{rid}: xmax must be a positive number")
        # every rule must pass through normal at the midpoint (24 mEq/L and 40 mmHg), within its tolerance
        if all(isinstance(rules.get(k), dict) and num(rules[k].get("slope")) and num(rules[k].get("intercept")) for k in rules) and mid:
            for rid in ("metAcid", "metAlk"):
                if rid in rules:
                    v = rules[rid]["slope"] * mid.get("hco3", 24) + rules[rid]["intercept"]
                    need(abs(v - mid.get("paco2", 40)) <= (rules[rid].get("tol") or 0) + 2.5, f"abg.rules.{rid}: expected PaCO2 at HCO3 {mid.get('hco3')} is {v:.1f}, far from {mid.get('paco2')}")
            for rid in ("respAcidAcute", "respAcidChronic", "respAlkAcute", "respAlkChronic"):
                if rid in rules:
                    v = rules[rid]["slope"] * mid.get("paco2", 40) + rules[rid]["intercept"]
                    need(abs(v - mid.get("hco3", 24)) <= 0.01, f"abg.rules.{rid}: expected HCO3 at PaCO2 {mid.get('paco2')} is {v:.2f}, not {mid.get('hco3')}")

    rg = data.get("regional")
    if rg is not None:
        num = lambda v: isinstance(v, (int, float)) and not isinstance(v, bool)
        derm = ["C2", "C3", "C4", "C5", "C6", "C7", "C8"] + [f"T{i}" for i in range(1, 13)] + [f"L{i}" for i in range(1, 6)] + [f"S{i}" for i in range(1, 6)]
        lvl = lambda v: isinstance(v, str) and bool(re.search(r"[CTLS]\d{1,2}", v.upper())) and re.search(r"[CTLS]\d{1,2}", v.upper()).group(0) in derm
        texts = lambda v: v is None or (isinstance(v, str) and v.strip()) or (isinstance(v, list) and v and all(isinstance(x, str) and x.strip() for x in v))
        fig = rg.get("figure") or {}
        need(isinstance(fig.get("box"), list) and len(fig["box"]) == 2 and all(num(x) and x > 0 for x in fig["box"]), "regional.figure.box must be [width, height]")
        need(isinstance(fig.get("outline"), str) and re.fullmatch(r"[MLCZ0-9.\- ,]+", fig["outline"] or "") is not None and fig["outline"].startswith("M") and fig["outline"].rstrip().endswith("Z"),
             "regional.figure.outline must be absolute M/L/C/Z path data, closed")
        need(all(num((fig.get("head") or {}).get(k)) for k in ("cx", "cy", "rx", "ry")), "regional.figure.head needs cx, cy, rx, ry")
        for view, lms in (fig.get("landmarks") or {}).items():
            need(view in ("front", "back"), f"regional.figure.landmarks: unknown view {view}")
            for lm in lms:
                need((lm.get("kind") == "dot" and num(lm.get("x")) and num(lm.get("y"))) or (lm.get("kind") == "line" and isinstance(lm.get("pts"), list) and len(lm["pts"]) >= 2),
                     f"regional.figure.landmarks.{view}: a landmark is a dot (x, y) or a line (pts)")
        region_ids = []
        for r_ in fig.get("regions") or []:
            rid = r_.get("id")
            region_ids.append(rid)
            need(isinstance(rid, str) and rid and isinstance(r_.get("name"), str) and r_["name"], "regional.figure.regions: id and name required")
            views = r_.get("views") or {}
            need(views and set(views) <= {"front", "back"}, f"regional region {rid}: views are front and/or back")
            for v, polys in views.items():
                need(isinstance(polys, list) and 1 <= len(polys) <= 2, f"regional region {rid}.{v}: one polygon (midline) or two (paired)")
                for poly in polys or []:
                    need(isinstance(poly, list) and len(poly) >= 3 and all(isinstance(p_, list) and len(p_) == 2 and all(num(c) for c in p_) for p_ in poly), f"regional region {rid}.{v}: polygons are 3+ [x, y] points")
        need(len(region_ids) == len(set(region_ids)) and region_ids, "regional.figure.regions: ids must be unique")
        group_ids = [g.get("id") for g in rg.get("blockGroups") or []]
        need(group_ids and len(group_ids) == len(set(group_ids)), "regional.blockGroups: unique ids required")
        src_ids = {s_.get("id") for s_ in rg.get("sources") or []}
        for s_ in rg.get("sources") or []:
            need(isinstance(s_.get("citation"), str) and s_["citation"].strip(), f"regional source {s_.get('id')}: citation required")
            need(s_.get("url") is None or str(s_["url"]).startswith("https://"), f"regional source {s_.get('id')}: url must be https")
        block_ids = []
        sono_items = {"band", "muscle", "fascia", "bone", "pleura", "artery", "vein", "nerve", "la", "text"}
        for b in rg.get("blocks") or []:
            bid = b.get("id")
            block_ids.append(bid)
            need(isinstance(b.get("name"), str) and b["name"], f"regional block {bid}: name required")
            need(b.get("group") in group_ids, f"regional block {bid}: group must be a listed blockGroup")
            for k in ("indications", "coverage", "position", "equipment", "target", "volume", "onset", "cautions", "tips"):
                need(texts(b.get(k)), f"regional block {bid}: {k} must be text or a list of text")
            need(b.get("volume"), f"regional block {bid}: volume required")
            need(isinstance(b.get("url"), str) and b["url"].startswith("https://www.nysora.com/"), f"regional block {bid}: url must be a NYSORA page")
            art = b.get("art")
            if art:
                pr = art.get("probe")
                need(pr is None or (pr.get("view") in ("front", "back") and num(pr.get("x")) and num(pr.get("y"))), f"regional block {bid}: probe needs view, x, y")
                so = art.get("sono")
                if so:
                    need(so.get("kind", "linear") in ("linear", "curved"), f"regional block {bid}: sono kind is linear or curved")
                    for it in so.get("items") or []:
                        need(it.get("t") in sono_items, f"regional block {bid}: unknown sono item {it.get('t')}")
                    nd = so.get("needle")
                    need(nd is None or (len(nd.get("from") or []) == 2 and len(nd.get("to") or []) == 2), f"regional block {bid}: needle is from/to points")
        need(len(block_ids) == len(set(block_ids)) and block_ids, "regional.blocks: unique ids required")
        rmap = rg.get("map") or {}
        for rid in region_ids:
            need(rid in rmap, f"regional.map: region {rid} has no entry")
        for rid, m in rmap.items():
            need(rid in region_ids, f"regional.map: {rid} is not a figure region")
            n = m.get("neuraxial")
            if n:
                need(isinstance(n.get("technique"), str) and n["technique"], f"regional.map.{rid}: neuraxial technique required")
                need(n.get("level") is None or lvl(n["level"]), f"regional.map.{rid}: neuraxial level must name a dermatome")
            for b in m.get("blocks") or []:
                need(b.get("id") in block_ids, f"regional.map.{rid}: block {b.get('id')} is not listed")
                need(b.get("role", "primary") in ("primary", "alternative"), f"regional.map.{rid}: role is primary or alternative")
        nx = rg.get("neuraxial")
        if nx is not None:
            pids = [p_.get("id") for p_ in nx.get("procedures") or []]
            need(pids and len(pids) == len(set(pids)), "regional.neuraxial.procedures: unique ids required")
            for p_ in nx.get("procedures") or []:
                need(isinstance(p_.get("name"), str) and p_["name"], f"regional.neuraxial {p_.get('id')}: name required")
                need(lvl(p_.get("level")), f"regional.neuraxial {p_.get('id')}: level must name a dermatome")
                for k in ("technique", "insertion", "spinal", "epidural", "adjuvants", "notes"):
                    need(texts(p_.get(k)), f"regional.neuraxial {p_.get('id')}: {k} must be text or a list of text")
                need(p_.get("spinal") or p_.get("epidural"), f"regional.neuraxial {p_.get('id')}: needs spinal or epidural dosing")
            for t in nx.get("tables") or []:
                cols = t.get("columns") or []
                need(isinstance(t.get("title"), str) and cols, "regional.neuraxial.tables: title and columns required")
                for row in t.get("rows") or []:
                    need(isinstance(row, list) and len(row) == len(cols), f"regional.neuraxial table {t.get('title')}: row width matches columns")
            for s_ in nx.get("sources") or []:
                need(isinstance(s_.get("citation"), str) and s_["citation"].strip(), f"regional.neuraxial source {s_.get('id')}: citation required")

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
