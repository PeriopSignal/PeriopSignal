#!/usr/bin/env python3
"""Make sure the app's bundle identifiers exist in the Apple Developer account with the right
capabilities, using the App Store Connect API (idempotent). Runs on the CI runner before archiving.

Env: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8 (contents of the .p8 file).
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

BASE = "https://api.appstoreconnect.apple.com/v1"
APPS = [
    ("org.periopsignal.app", "Periop Signal", ["PUSH_NOTIFICATIONS", "ICLOUD"]),
    ("org.periopsignal.app.widget", "Periop Signal Widget", []),
]

def token():
    now = int(time.time())
    return jwt.encode({"iss": ISSUER, "iat": now, "exp": now + 1200, "aud": "appstoreconnect-v1"}, P8, algorithm="ES256", headers={"kid": KEY_ID})

def call(method, path, body=None):
    req = urllib.request.Request(BASE + path, method=method, data=json.dumps(body).encode() if body else None)
    req.add_header("Authorization", "Bearer " + token())
    req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return r.status, json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read() or b"{}")

def main():
    status, data = call("GET", "/bundleIds?limit=200&filter[platform]=IOS")
    if status != 200:
        print("Cannot list bundle ids:", status, json.dumps(data)[:800]); sys.exit(1)
    existing = {b["attributes"]["identifier"]: b for b in data.get("data", [])}
    for ident, name, caps in APPS:
        if ident in existing:
            bid = existing[ident]["id"]; print(f"{ident}: present ({bid})")
        else:
            status, data = call("POST", "/bundleIds", {"data": {"type": "bundleIds", "attributes": {"identifier": ident, "name": name, "platform": "IOS"}}})
            if status not in (200, 201):
                print(f"{ident}: create failed {status} {json.dumps(data)[:800]}"); sys.exit(1)
            bid = data["data"]["id"]; print(f"{ident}: created ({bid})")
        if caps:
            status, data = call("GET", f"/bundleIds/{bid}/bundleIdCapabilities")
            have = {c["attributes"]["capabilityType"] for c in data.get("data", [])} if status == 200 else set()
            for cap in caps:
                if cap in have:
                    print(f"  {cap}: already enabled"); continue
                body = {"data": {"type": "bundleIdCapabilities", "attributes": {"capabilityType": cap}, "relationships": {"bundleId": {"data": {"type": "bundleIds", "id": bid}}}}}
                if cap == "ICLOUD":
                    body["data"]["attributes"]["settings"] = [{"key": "ICLOUD_VERSION", "options": [{"key": "XCODE_6"}]}]
                status, data = call("POST", "/bundleIdCapabilities", body)
                print(f"  {cap}: {'enabled' if status in (200, 201) else 'failed ' + str(status) + ' ' + json.dumps(data)[:400]}")
    print("Bundle identifiers ready.")

if __name__ == "__main__":
    main()
