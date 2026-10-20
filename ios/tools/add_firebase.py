#!/usr/bin/env python3
"""Add the Firebase Messaging package to project.yml (run on CI only when GoogleService-Info.plist
is available). Keeps day-to-day simulator builds fast and free of the Firebase dependency."""
import re, sys, pathlib

spec = pathlib.Path(__file__).resolve().parents[1] / "project.yml"
s = spec.read_text()
if "firebase-ios-sdk" in s:
    print("Firebase already in project.yml"); sys.exit(0)

s = s.replace("\ntargets:\n", '''
packages:
  Firebase:
    url: https://github.com/firebase/firebase-ios-sdk
    from: "11.0.0"

targets:
''', 1)

# dependencies of the app target
s = re.sub(r"(  PeriopSignal:\n(?:.*\n)*?    dependencies:\n)", r"\1      - package: Firebase\n        product: FirebaseMessaging\n", s, count=1)
spec.write_text(s)
print("Firebase Messaging added to project.yml")
