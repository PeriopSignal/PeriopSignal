#!/usr/bin/env python3
"""Validate posts.json: required fields, formats, allowed values, uniqueness, and the optional
objects that the app uses (glance, quiz, citation). Exit code 1 on any problem.

    python3 -I tools/validate_posts.py [posts.json]
"""
import json
import re
import sys

REQUIRED = ["id", "date", "dateApprox", "addedAt", "journal", "jshort", "kind", "topics", "headline", "summary",
            "takeHome", "authorLimitations", "takeHomeBy", "authorBasis", "deepDive", "url", "impact", "trialName", "firstAuthor"]
TOPICS = {"cardiac", "cardiacSurgery", "mcs", "echo", "thoracic", "regional", "ob", "trauma", "pediatric", "pedsCardiac", "liver", "criticalCare", "general"}
KINDS = {"RCT", "Guideline", "Consensus", "Meta-analysis", "Observational", "Registry", "FDA/Regulatory", "Device", "Safety alert", "Trial update", "Conference"}
RESEARCH = {"RCT", "Observational", "Registry", "Meta-analysis", "Trial update"}
DATE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
GLANCE_KEYS = ["design", "n", "outcome", "result"]
QUIZ_KEYS = ["question", "options", "answer", "explanation"]
CITATION_KEYS = ["title", "authors", "journal", "year", "volume", "issue", "pages", "doi"]


def check(path="posts.json"):
    problems = []
    data = json.load(open(path, encoding="utf-8"))
    posts = data.get("posts")
    if not isinstance(posts, list) or not posts:
        return ["posts is missing or empty"]
    ids, urls = {}, {}
    for i, p in enumerate(posts):
        tag = f"posts[{i}] {p.get('id', '?')}"
        for k in REQUIRED:
            if k not in p:
                problems.append(f"{tag}: missing {k}")
        pid = p.get("id", "")
        if not re.fullmatch(r"[a-z0-9][a-z0-9-]*", pid or ""):
            problems.append(f"{tag}: id must be lowercase letters, digits and hyphens")
        if pid in ids:
            problems.append(f"{tag}: duplicate id (also posts[{ids[pid]}])")
        ids[pid] = i
        u = (p.get("url") or "").strip().lower()
        if not u.startswith("http"):
            problems.append(f"{tag}: url must be a link")
        if u in urls:
            problems.append(f"{tag}: duplicate url (also posts[{urls[u]}])")
        urls[u] = i
        for k in ("date", "addedAt"):
            if not DATE.match(str(p.get(k, ""))):
                problems.append(f"{tag}: {k} must be YYYY-MM-DD")
        if p.get("kind") not in KINDS:
            problems.append(f"{tag}: kind {p.get('kind')!r} not allowed")
        if not isinstance(p.get("topics"), list) or not p["topics"] or not set(p["topics"]) <= TOPICS:
            problems.append(f"{tag}: topics must be a non-empty list from the allowed set")
        if p.get("impact") not in (1, 2, 3):
            problems.append(f"{tag}: impact must be 1, 2 or 3")
        if len(p.get("headline", "")) > 140:
            problems.append(f"{tag}: headline longer than 140 characters")
        th = p.get("takeHome")
        if not isinstance(th, list) or not (1 <= len(th) <= 4):
            problems.append(f"{tag}: takeHome must have 1-4 bullets")
        if not isinstance(p.get("authorLimitations"), list):
            problems.append(f"{tag}: authorLimitations must be a list")
        if p.get("takeHomeBy") not in ("authors", "editor", ""):
            problems.append(f"{tag}: takeHomeBy must be authors, editor or empty")
        if p.get("authorBasis") not in ("full text", "abstract", "summary page", ""):
            problems.append(f"{tag}: authorBasis not allowed")
        words = len((p.get("deepDive") or "").split())
        if words < 80:
            problems.append(f"{tag}: deepDive has only {words} words")

        # Optional: at-a-glance strip
        g = p.get("glance")
        if g is not None:
            if not isinstance(g, dict) or set(g) - set(GLANCE_KEYS):
                problems.append(f"{tag}: glance must be an object with keys from {GLANCE_KEYS}")
            else:
                for k in GLANCE_KEYS:
                    v = g.get(k, "")
                    if not isinstance(v, str):
                        problems.append(f"{tag}: glance.{k} must be a string")
                    elif len(v) > 90:
                        problems.append(f"{tag}: glance.{k} longer than 90 characters")
                if not any(g.get(k) for k in GLANCE_KEYS):
                    problems.append(f"{tag}: glance is empty; omit it instead")

        # Optional: one multiple-choice question answerable from the post
        q = p.get("quiz")
        if q is not None:
            if not isinstance(q, dict) or set(q) != set(QUIZ_KEYS):
                problems.append(f"{tag}: quiz must be an object with exactly {QUIZ_KEYS}")
            else:
                if not isinstance(q["question"], str) or not (20 <= len(q["question"]) <= 260):
                    problems.append(f"{tag}: quiz.question must be 20-260 characters")
                opts = q["options"]
                if not isinstance(opts, list) or len(opts) != 4 or any(not isinstance(o, str) or not o.strip() for o in opts):
                    problems.append(f"{tag}: quiz.options must be 4 non-empty strings")
                elif len({o.strip().lower() for o in opts}) != 4:
                    problems.append(f"{tag}: quiz.options must be distinct")
                elif any(len(o) > 120 for o in opts):
                    problems.append(f"{tag}: quiz option longer than 120 characters")
                if not isinstance(q["answer"], int) or isinstance(q["answer"], bool) or not 0 <= q["answer"] <= 3:
                    problems.append(f"{tag}: quiz.answer must be 0-3")
                if not isinstance(q["explanation"], str) or not (20 <= len(q["explanation"]) <= 420):
                    problems.append(f"{tag}: quiz.explanation must be 20-420 characters")

        # Optional: bibliographic record for citations
        c = p.get("citation")
        if c is not None:
            if not isinstance(c, dict) or set(c) - set(CITATION_KEYS):
                problems.append(f"{tag}: citation must be an object with keys from {CITATION_KEYS}")
            else:
                if not isinstance(c.get("title"), str) or not c["title"].strip():
                    problems.append(f"{tag}: citation.title required")
                if not isinstance(c.get("authors"), list) or any(not isinstance(a, str) for a in c["authors"]):
                    problems.append(f"{tag}: citation.authors must be a list of strings")
                for k in ("journal", "volume", "issue", "pages", "doi"):
                    if k in c and not isinstance(c[k], str):
                        problems.append(f"{tag}: citation.{k} must be a string")
                if "year" in c and not (isinstance(c["year"], int) and 1900 < c["year"] < 2100):
                    problems.append(f"{tag}: citation.year must be a year")
        t = p.get("title")
        if t is not None and (not isinstance(t, str) or not t.strip()):
            problems.append(f"{tag}: title must be a non-empty string when present")
    return problems


if __name__ == "__main__":
    path = sys.argv[1] if len(sys.argv) > 1 else "posts.json"
    probs = check(path)
    data = json.load(open(path, encoding="utf-8"))
    n = len(data.get("posts", []))
    with_quiz = sum(1 for p in data.get("posts", []) if p.get("quiz"))
    with_glance = sum(1 for p in data.get("posts", []) if p.get("glance"))
    with_cit = sum(1 for p in data.get("posts", []) if p.get("citation"))
    if probs:
        print("\n".join(probs[:60]))
        print(f"FAILED: {len(probs)} problem(s) in {n} posts")
        sys.exit(1)
    print(f"OK: {n} posts; {with_quiz} with quiz, {with_glance} with glance, {with_cit} with citation")
