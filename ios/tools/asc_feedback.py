#!/usr/bin/env python3
"""Fetch TestFlight crash reports for the app from the App Store Connect API (beta feedback crash submissions and
their crash logs) and write them for diagnosis. Testers' emails, comments and locale are left out, because the
results branch is public.

Usage: python3 ios/tools/asc_feedback.py OUT_DIR
Env: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8 (contents of the .p8 file, or base64 of it).
"""
import json, os, sys, time, urllib.request, urllib.error

try:
    import jwt  # PyJWT
except ImportError:
    print("PyJWT missing: pip3 install pyjwt cryptography", file=sys.stderr); sys.exit(2)

KEY_ID = os.environ["ASC_KEY_ID"].strip()
ISSUER = os.environ["ASC_ISSUER_ID"].strip()
P8 = os.environ["ASC_KEY_P8"].strip()
if "BEGIN PRIVATE KEY" not in P8:
    import base64
    P8 = base64.b64decode(P8).decode()

BASE = "https://api.appstoreconnect.apple.com"
BUNDLE = "org.periopsignal.app"
# Technical fields only.
KEEP = ["createdDate", "deviceModel", "osVersion", "architecture", "appPlatform", "devicePlatform", "deviceFamily",
        "appUptimeInMilliseconds", "batteryPercentage", "connectionType", "buildBundleId"]


def token():
    now = int(time.time())
    return jwt.encode({"iss": ISSUER, "iat": now, "exp": now + 1200, "aud": "appstoreconnect-v1"}, P8,
                      algorithm="ES256", headers={"kid": KEY_ID})


def get(path):
    req = urllib.request.Request(path if path.startswith("http") else BASE + path)
    req.add_header("Authorization", "Bearer " + token())
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return r.status, json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        try:
            return e.code, json.loads(e.read() or b"{}")
        except Exception:
            return e.code, {}


def main(out):
    os.makedirs(out, exist_ok=True)
    summary = []
    status, data = get(f"/v1/apps?filter[bundleId]={BUNDLE}")
    if status != 200 or not data.get("data"):
        summary.append(f"Cannot find the app: {status} {json.dumps(data)[:400]}")
        return finish(out, summary, 1)
    app = data["data"][0]["id"]
    status, data = get(f"/v1/apps/{app}/betaFeedbackCrashSubmissions?limit=20&include=build&fields[builds]=version,uploadedDate")
    if status != 200:
        summary.append(f"Crash submissions not available: {status} {json.dumps(data)[:600]}")
        return finish(out, summary, 1)
    builds = {b["id"]: b.get("attributes", {}) for b in data.get("included", []) if b.get("type") == "builds"}
    subs = data.get("data", [])
    summary.append(f"{len(subs)} crash submission(s), newest first")
    for i, s in enumerate(subs):
        a = s.get("attributes", {})
        b = (s.get("relationships", {}).get("build", {}).get("data") or {}).get("id")
        info = {k: a.get(k) for k in KEEP if a.get(k) is not None}
        if b in builds:
            info["build"] = builds[b].get("version")
        summary.append(f"\n## {i + 1}. {a.get('createdDate', '?')} · build {info.get('build', '?')} · {a.get('deviceModel', '?')} · iOS {a.get('osVersion', '?')}")
        summary.append(json.dumps(info, indent=1))
        st, log = get(f"/v1/betaFeedbackCrashSubmissions/{s['id']}/crashLog")
        text = (log.get("data") or {}).get("attributes", {}).get("logText") if st == 200 else None
        if not text:
            summary.append(f"(no crash log: {st} {json.dumps(log)[:300]})")
            continue
        name = f"crash-{i + 1}.txt"
        with open(os.path.join(out, name), "w", encoding="utf-8") as f:
            f.write(text)
        lines = text.splitlines()
        keys = [l for l in lines if l.startswith(("Exception Type", "Exception Codes", "Exception Note", "Termination Reason",
                                                    "Triggered by Thread", "Crashed Thread", "Version", "OS Version"))]
        summary.append("\n".join(keys[:12]))
        # The crashed thread's frames.
        start = next((k for k, l in enumerate(lines) if "Crashed" in l and l.startswith("Thread")), None)
        if start is not None:
            summary.append("\n".join(lines[start:start + 40]))
        summary.append(f"(full log: {name})")
    return finish(out, summary, 0)


def finish(out, summary, code):
    text = "\n".join(summary)
    with open(os.path.join(out, "SUMMARY.md"), "w", encoding="utf-8") as f:
        f.write(text + "\n")
    print(text[:20000])
    return code


if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else "feedback"))
