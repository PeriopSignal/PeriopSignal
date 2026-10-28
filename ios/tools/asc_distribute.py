#!/usr/bin/env python3
"""After a TestFlight upload: wait for Apple to finish processing the build, answer export compliance,
set "What to Test", submit the build for Beta App Review and add it to a tester group, through the
App Store Connect API. Idempotent: running it again for a build that is already in the group is a no-op.

Env: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8 (contents of the .p8 file, plain or base64).
Usage: asc_distribute.py --version 1.3.1 --build 9 [--group Colleagues] [--notes "..."] [--wait-minutes 60]
"""
import argparse, base64, json, os, sys, time, urllib.error, urllib.parse, urllib.request

try:
    import jwt  # PyJWT
except ImportError:
    print("PyJWT missing: pip3 install pyjwt cryptography", file=sys.stderr); sys.exit(2)

BUNDLE_ID = "org.periopsignal.app"
BASE = "https://api.appstoreconnect.apple.com/v1"
KEY_ID = os.environ.get("ASC_KEY_ID", "").strip()
ISSUER = os.environ.get("ASC_ISSUER_ID", "").strip()
P8 = os.environ.get("ASC_KEY_P8", "").strip()
if P8 and "BEGIN PRIVATE KEY" not in P8:
    P8 = base64.b64decode(P8).decode()


def token():
    now = int(time.time())
    return jwt.encode({"iss": ISSUER, "iat": now, "exp": now + 1200, "aud": "appstoreconnect-v1"}, P8,
                      algorithm="ES256", headers={"kid": KEY_ID})


def call(method, path, body=None, params=None):
    """One API call; network hiccups, 429 and 5xx are retried (Apple's API drops connections now and then)."""
    url = BASE + path + ("?" + urllib.parse.urlencode(params) if params else "")
    data = json.dumps(body).encode() if body else None
    for attempt in range(5):
        req = urllib.request.Request(url, method=method, data=data)
        req.add_header("Authorization", "Bearer " + token())
        req.add_header("Content-Type", "application/json")
        try:
            with urllib.request.urlopen(req, timeout=90) as r:
                return r.status, json.loads(r.read() or b"{}")
        except urllib.error.HTTPError as e:
            try:
                payload = json.loads(e.read() or b"{}")
            except ValueError:
                payload = {}
            if e.code not in (429, 500, 502, 503, 504) or attempt == 4:
                return e.code, payload
            print(f"  {method} {path}: HTTP {e.code}, retrying", flush=True)
        except (urllib.error.URLError, TimeoutError, ConnectionError, OSError) as e:
            if attempt == 4:
                raise
            print(f"  {method} {path}: {type(e).__name__}, retrying", flush=True)
        time.sleep(5 * 2 ** attempt)


def err(data):
    errors = data.get("errors") or []
    if errors:
        e = errors[0]
        return (e.get("detail") or e.get("title") or json.dumps(e))[:300]
    return json.dumps(data)[:300]


def fail(msg):
    print("::error::" + msg)
    sys.exit(1)


def human(state):
    return (state or "unknown").replace("_", " ").lower()


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--version", required=True, help="marketing version, e.g. 1.3.1")
    ap.add_argument("--build", required=True, help="build number (the release run number)")
    ap.add_argument("--group", default="Colleagues", help="TestFlight group name; empty = do not add to a group")
    ap.add_argument("--notes", default="", help='"What to Test" text; empty keeps what is there, or writes a generic line')
    ap.add_argument("--wait-minutes", type=int, default=60)
    a = ap.parse_args(argv)
    if not (KEY_ID and ISSUER and P8):
        fail("ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY_P8 must be set")

    # 1. The app.
    st, d = call("GET", "/apps", params={"filter[bundleId]": BUNDLE_ID, "fields[apps]": "name,bundleId"})
    apps = d.get("data", []) if st == 200 else []
    if not apps:
        fail(f"No app with bundle id {BUNDLE_ID} in App Store Connect ({st}: {err(d)})")
    app_id, app_name = apps[0]["id"], apps[0]["attributes"]["name"]

    # 2. Wait for Apple to process the build (usually 5-20 minutes after the upload).
    deadline = time.time() + a.wait_minutes * 60
    build = None
    while True:
        st, d = call("GET", "/builds", params={
            "filter[app]": app_id, "filter[version]": a.build, "filter[preReleaseVersion.version]": a.version,
            "fields[builds]": "version,processingState,uploadedDate,usesNonExemptEncryption,expired",
            "sort": "-uploadedDate", "limit": 5})
        if st != 200:
            fail(f"Cannot list builds ({st}: {err(d)})")
        items = d.get("data", [])
        if items:
            build = items[0]
            state = build["attributes"].get("processingState")
            if state == "VALID":
                break
            if state in ("FAILED", "INVALID"):
                fail(f"Apple could not process build {a.version} ({a.build}): {human(state)}. Check the email from App Store Connect.")
            print(f"build {a.version} ({a.build}) is {human(state)}; waiting", flush=True)
        else:
            print(f"build {a.version} ({a.build}) not visible yet; waiting", flush=True)
        if time.time() > deadline:
            fail(f"Build {a.version} ({a.build}) did not finish processing within {a.wait_minutes} minutes. "
                 f"Run the 'TestFlight distribute' workflow later with version={a.version} build={a.build}.")
        time.sleep(60)
    bid = build["id"]
    print(f"{app_name}: build {a.version} ({a.build}) processed")

    # 3. Export compliance (Info.plist already declares standard encryption; this covers a build that lacks it).
    if build["attributes"].get("usesNonExemptEncryption") is None:
        st, d = call("PATCH", f"/builds/{bid}", {"data": {"type": "builds", "id": bid, "attributes": {"usesNonExemptEncryption": False}}})
        print("export compliance:", "standard encryption only" if st == 200 else f"not set ({st}: {err(d)})")

    # 4. "What to Test".
    st, d = call("GET", f"/builds/{bid}/betaBuildLocalizations", params={"fields[betaBuildLocalizations]": "locale,whatsNew"})
    existing = {l["attributes"].get("locale"): l for l in d.get("data", [])} if st == 200 else {}
    current = (existing.get("en-US", {}).get("attributes", {}).get("whatsNew") or "").strip()
    notes = a.notes.strip()
    if notes or not current:
        text = notes or f"Periop Signal {a.version} (build {a.build})."
        if "en-US" in existing:
            lid = existing["en-US"]["id"]
            st, d = call("PATCH", f"/betaBuildLocalizations/{lid}", {"data": {"type": "betaBuildLocalizations", "id": lid, "attributes": {"whatsNew": text}}})
        else:
            st, d = call("POST", "/betaBuildLocalizations", {"data": {"type": "betaBuildLocalizations", "attributes": {"locale": "en-US", "whatsNew": text},
                                                                      "relationships": {"build": {"data": {"type": "builds", "id": bid}}}}})
        print("what to test:", f"set ({text[:80]})" if st in (200, 201) else f"not set ({st}: {err(d)})")
    else:
        print(f"what to test: kept ({current[:80]})")

    if not a.group.strip():
        print("No group given; done.")
        return

    # 5. The tester group.
    st, d = call("GET", "/betaGroups", params={"filter[app]": app_id, "fields[betaGroups]": "name,isInternalGroup,publicLinkEnabled", "limit": 200})
    groups = d.get("data", []) if st == 200 else []
    match = [g for g in groups if g["attributes"]["name"].strip().lower() == a.group.strip().lower()]
    if not match:
        names = ", ".join(g["attributes"]["name"] for g in groups) or "none"
        fail(f"No TestFlight group named '{a.group}' (groups in App Store Connect: {names}). "
             "Create it under TestFlight > External Testing, or pass the right name as the 'group' input.")
    group = match[0]
    gid, gname = group["id"], group["attributes"]["name"]
    external = not group["attributes"].get("isInternalGroup", False)

    # 6. Beta App Review (external groups only). A build that was already submitted is left alone.
    if external:
        st, d = call("GET", f"/builds/{bid}/betaAppReviewSubmission", params={"fields[betaAppReviewSubmissions]": "betaReviewState"})
        state = (d.get("data") or {}).get("attributes", {}).get("betaReviewState") if st == 200 else None
        if state:
            print("beta app review:", human(state))
        else:
            st, d = call("POST", "/betaAppReviewSubmissions", {"data": {"type": "betaAppReviewSubmissions",
                                                                        "relationships": {"build": {"data": {"type": "builds", "id": bid}}}}})
            if st in (200, 201):
                print("beta app review: submitted")
            else:
                print(f"::warning::beta app review not submitted ({st}: {err(d)}). Complete Test Information under TestFlight in "
                      f"App Store Connect, then run 'TestFlight distribute' with version={a.version} build={a.build}.")

    # 7. Add the build to the group.
    st, d = call("POST", f"/betaGroups/{gid}/relationships/builds", {"data": [{"type": "builds", "id": bid}]})
    if st in (200, 204):
        print(f"added to group '{gname}'" + (" (public link on)" if group["attributes"].get("publicLinkEnabled") else ""))
    elif st == 409 and "already" in json.dumps(d).lower():
        print(f"already in group '{gname}'")
    else:
        fail(f"Could not add the build to '{gname}' ({st}: {err(d)})")

    # 8. Where it stands.
    st, d = call("GET", f"/builds/{bid}/buildBetaDetail", params={"fields[buildBetaDetails]": "externalBuildState,internalBuildState"})
    if st == 200 and d.get("data"):
        attrs = d["data"]["attributes"]
        print("external testing:", human(attrs.get("externalBuildState")), "· internal:", human(attrs.get("internalBuildState")))


if __name__ == "__main__":
    main()
