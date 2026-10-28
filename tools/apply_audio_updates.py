#!/usr/bin/env python3
"""Merge audio links into posts.json: python3 -I tools/apply_audio_updates.py audio-updates.json [posts.json]

audio-updates.json is {"<post id>": {"url": ..., "seconds": ..., "bytes": ..., "voice": ...}, ...}, written by
tools/synthesize_audio.py. Used by the workflow to re-apply a run's results onto the latest posts.json
after a fetch, so two writers never conflict on the file.
"""
import json
import sys

updates = json.load(open(sys.argv[1], encoding="utf-8"))
path = sys.argv[2] if len(sys.argv) > 2 else "posts.json"
data = json.load(open(path, encoding="utf-8"))
n = 0
for p in data["posts"]:
    a = updates.get(p["id"])
    if a and p.get("audio") != a:
        p["audio"] = a
        n += 1
if n:
    json.dump(data, open(path, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
print(f"applied {n} audio link(s)")
