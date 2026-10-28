#!/usr/bin/env python3
"""Read each post aloud with Google Cloud Text-to-Speech (Chirp 3 HD) and publish the MP3s.

    python3 -I tools/synthesize_audio.py [posts.json] [--all] [--limit N] [--voice en-US-Chirp3-HD-Charon] [--dry-run]

For every post without `audio` (all DOI-or-not posts; `--all` regenerates, e.g. after a voice change),
the script builds the spoken text the app would speak (headline, source line, take-home, overview,
stated limitations), synthesizes it in chunks under Google's request limit, joins the chunks with
ffmpeg, uploads `<id>.mp3` to the repository's "audio" GitHub release, and writes
    "audio": {"url": ..., "seconds": N, "bytes": N, "voice": ...}
into the post. Needs GOOGLE_TTS_API_KEY (an API key restricted to the Text-to-Speech API) and GH_TOKEN
with contents: write. Without the key it exits 0 after saying so, so the workflow is a no-op until the
owner adds it. Runs in GitHub Actions (.github/workflows/audio.yml).
"""
import base64
import json
import os
import re
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request

REPO = os.environ.get("GITHUB_REPOSITORY", "PeriopSignal/PeriopSignal")
RELEASE_TAG = "audio"
DEFAULT_VOICE = {"kokoro": "af_heart", "google": "en-US-Chirp3-HD-Charon"}
KOKORO_DIR = os.environ.get("KOKORO_DIR", "kokoro")
_kokoro = None
MAX_CHUNK_BYTES = 4500          # Google's synthesize limit is 5,000 bytes of input
TTS_URL = "https://texttospeech.googleapis.com/v1/text:synthesize"

# ---------------------------------------------------------------- spoken text (mirrors ios SpeechPlayer)

SWAPS = [
    (r"/kg/min\b", " per kilogram per minute"), (r"/kg/h\b", " per kilogram per hour"), (r"/kg\b", " per kilogram"),
    (r"/min\b", " per minute"), (r"/h\b", " per hour"), (r"/L\b", " per litre"), (r"/dL\b", " per decilitre"),
    (r"\bvs\.?\b", "versus"), (r"\bmcg\b", "micrograms"), (r"\bμg\b", "micrograms"), (r"\bkg\b", "kilograms"),
    (r"\bmL\b", "millilitres"), (r"\bmmHg\b", "millimetres of mercury"), (r"\bh\b(?=[\s,.;])", "hours"),
    (r"\bmin\b(?=[\s,.;])", "minutes"), (r"≥", "at least "), (r"≤", "at most "), (r"\bn\s?=\s?", "n equals "),
    (r"\bCI\b", "confidence interval"), (r"\bRCT\b", "randomized trial"), (r"\bICU\b", "I C U"), (r"\bOR\b(?=\s\d)", "odds ratio"),
    (r"\bHR\b(?=\s\d)", "hazard ratio"), (r"\bRR\b(?=\s\d)", "relative risk"), (r"\bTEE\b", "T E E"),
]


def spoken(s):
    t = s.replace("**", "").replace("__", "").replace("`", "")
    t = re.sub(r"\[([^\]]+)\]\([^)]*\)", r"\1", t)
    for pat, rep in SWAPS:
        t = re.sub(pat, rep, t)
    return t.strip()


def markdown_blocks(src):
    out, para, lst = [], [], []

    def flush_p():
        if para:
            out.append(("p", " ".join(para))); para.clear()

    def flush_l():
        if lst:
            out.append(("l", list(lst))); lst.clear()

    for raw in src.split("\n"):
        line = raw.strip()
        if not line:
            flush_p(); flush_l(); continue
        m = re.match(r"^[-*•]\s+", line)
        if m:
            flush_p(); lst.append(line[m.end():]); continue
        m = re.match(r"^#{1,4}\s+", line)
        if m:
            flush_p(); flush_l(); out.append(("h", line[m.end():])); continue
        flush_l(); para.append(line)
    flush_p(); flush_l()
    return out


def display_date(s):
    import datetime
    try:
        d = datetime.date.fromisoformat(s[:10])
        return d.strftime("%b %-d, %Y")
    except Exception:
        return s


KIND_SPOKEN = {"RCT": "a randomized trial", "Guideline": "a guideline", "Consensus": "a consensus statement", "Meta-analysis": "a meta-analysis",
               "Observational": "an observational study", "Registry": "a registry study", "FDA/Regulatory": "a regulatory notice",
               "Device": "device news", "Safety alert": "a safety alert", "Trial update": "a trial update", "Conference": "a conference report"}


def segments(post):
    out = [spoken(post["headline"])]
    source = f"From {post['journal']}, {KIND_SPOKEN.get(post['kind'], post['kind'].lower())}"
    if post.get("trialName"):
        source += f", the {post['trialName']} trial"
    source += f", {display_date(post['date'])}."
    out.append(source)
    if post.get("takeHome"):
        out.append("The authors' key points." if post.get("takeHomeBy") == "authors" else "Take-home.")
        out.extend(spoken(b) for b in post["takeHome"])
    for kind, val in markdown_blocks(post.get("deepDive", "")):
        if kind == "l":
            out.extend(spoken(i) for i in val)
        else:
            out.append(spoken(val))
    if post.get("authorLimitations"):
        out.append("Limitations stated by the authors.")
        out.extend(spoken(b) for b in post["authorLimitations"])
    return [s for s in out if s]


def chunks(segs):
    """Join segments into paragraphs, grouped under the request limit."""
    groups, cur = [], ""
    for s in segs:
        piece = s if s.endswith((".", "!", "?", ":")) else s + "."
        candidate = (cur + "\n\n" + piece) if cur else piece
        if len(candidate.encode("utf-8")) > MAX_CHUNK_BYTES and cur:
            groups.append(cur); cur = piece
        else:
            cur = candidate
    if cur:
        groups.append(cur)
    # A single oversized paragraph (rare): split on sentences.
    final = []
    for g in groups:
        if len(g.encode("utf-8")) <= MAX_CHUNK_BYTES:
            final.append(g); continue
        buf = ""
        for sent in re.split(r"(?<=[.!?])\s+", g):
            cand = (buf + " " + sent) if buf else sent
            if len(cand.encode("utf-8")) > MAX_CHUNK_BYTES and buf:
                final.append(buf); buf = sent
            else:
                buf = cand
        if buf:
            final.append(buf)
    return final


# ---------------------------------------------------------------- Google TTS

def synthesize(text, voice, key):
    body = json.dumps({
        "input": {"text": text},
        "voice": {"languageCode": "en-US", "name": voice},
        "audioConfig": {"audioEncoding": "MP3", "speakingRate": 1.0},
    }).encode("utf-8")
    req = urllib.request.Request(f"{TTS_URL}?key={key}", data=body, headers={"Content-Type": "application/json"})
    for attempt in range(4):
        try:
            with urllib.request.urlopen(req, timeout=120) as r:
                return base64.b64decode(json.loads(r.read())["audioContent"])
        except urllib.error.HTTPError as e:
            detail = e.read().decode("utf-8", "replace")[:300]
            if e.code in (429, 500, 502, 503, 504) and attempt < 3:
                time.sleep(5 * (attempt + 1)); continue
            raise RuntimeError(f"TTS HTTP {e.code}: {detail}")
        except Exception:
            if attempt == 3:
                raise
            time.sleep(5 * (attempt + 1))


def synth_kokoro(segs, voice, out_path):
    """Paragraph by paragraph, with a pause between sections, straight to MP3."""
    import numpy as np
    import soundfile as sf
    from kokoro_onnx import Kokoro
    global _kokoro
    if _kokoro is None:
        _kokoro = Kokoro(os.path.join(KOKORO_DIR, "kokoro-v1.0.onnx"), os.path.join(KOKORO_DIR, "voices-v1.0.bin"))
    lang = "en-gb" if voice.startswith("b") else "en-us"
    pieces, sr = [], 24000
    for i, seg in enumerate(segs):
        text = seg if seg.endswith((".", "!", "?", ":")) else seg + "."
        samples, sr = _kokoro.create(text, voice=voice, speed=1.0, lang=lang)
        pieces.append(np.asarray(samples, dtype=np.float32))
        pause = 0.9 if i == 0 else (0.6 if text.endswith(("points.", "Take-home.", "authors.")) else 0.45)
        pieces.append(np.zeros(int(sr * pause), dtype=np.float32))
    wav = out_path + ".wav"
    sf.write(wav, np.concatenate(pieces), sr)
    # Podcast loudness (-16 LUFS) so the recordings sit at the same level as other spoken audio.
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav, "-af", "loudnorm=I=-16:TP=-1.5:LRA=11", "-ac", "1", "-b:a", "64k", out_path], check=True)
    os.remove(wav)


def synth_google(segs, voice, key, out_path, workdir, pid):
    files = []
    for i, chunk in enumerate(chunks(segs)):
        audio = synthesize(chunk, voice, key)
        fp = os.path.join(workdir, f"{pid}.{i}.mp3")
        open(fp, "wb").write(audio)
        files.append(fp)
        time.sleep(0.2)
    join_mp3(files, out_path)


def join_mp3(parts, out_path):
    if len(parts) == 1:
        os.replace(parts[0], out_path); return
    lst = out_path + ".txt"
    with open(lst, "w") as fh:
        for p in parts:
            fh.write(f"file '{p}'\n")
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-f", "concat", "-safe", "0", "-i", lst, "-c", "copy", out_path], check=True)


def duration(path):
    out = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "default=nw=1:nk=1", path],
                         capture_output=True, text=True, check=True).stdout.strip()
    return int(round(float(out)))


def ensure_release():
    if subprocess.run(["gh", "release", "view", RELEASE_TAG, "-R", REPO], capture_output=True).returncode != 0:
        subprocess.run(["gh", "release", "create", RELEASE_TAG, "-R", REPO, "--title", "Post audio",
                        "--notes", "One MP3 per post, read by Google Cloud Text-to-Speech. Written by .github/workflows/audio.yml.",
                        "--latest=false"], check=True)


def upload(path):
    subprocess.run(["gh", "release", "upload", RELEASE_TAG, path, "-R", REPO, "--clobber"], check=True)
    return f"https://github.com/{REPO}/releases/download/{RELEASE_TAG}/{os.path.basename(path)}"


# ---------------------------------------------------------------- main

def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    path = args[0] if args else "posts.json"
    force = "--all" in sys.argv
    dry = "--dry-run" in sys.argv
    engine = os.environ.get("TTS_ENGINE") or "kokoro"
    voice = os.environ.get("TTS_VOICE") or ""
    limit = None
    for i, a in enumerate(sys.argv):
        if a == "--limit" and i + 1 < len(sys.argv) and sys.argv[i + 1]:
            limit = int(sys.argv[i + 1])
        if a == "--voice" and i + 1 < len(sys.argv):
            voice = sys.argv[i + 1]
        if a == "--engine" and i + 1 < len(sys.argv):
            engine = sys.argv[i + 1]
    if engine not in DEFAULT_VOICE:
        sys.exit(f"unknown engine {engine}")
    voice = voice or DEFAULT_VOICE[engine]
    tag = f"{engine}:{voice}"
    key = os.environ.get("GOOGLE_TTS_API_KEY", "").strip()
    if engine == "google" and not key and not dry:
        print("No GOOGLE_TTS_API_KEY; nothing to synthesize.")
        return
    data = json.load(open(path, encoding="utf-8"))
    todo = [p for p in data["posts"] if force or not p.get("audio") or p["audio"].get("voice") != tag]
    if limit:
        todo = todo[:limit]
    print(f"{len(todo)} post(s) to synthesize with {tag}" + (" (dry run)" if dry else ""))
    if not todo:
        return
    if not dry:
        ensure_release()
    done, failed, total_chars = 0, [], 0
    updates = {}
    workdir = tempfile.mkdtemp(prefix="ps-audio-")
    started = time.time()
    for p in todo:
        segs = segments(p)
        total_chars += sum(len(c) for c in segs)
        if dry:
            print(f"  {p['id']}: {len(segs)} paragraph(s), {sum(len(c) for c in segs)} chars")
            continue
        try:
            out = os.path.join(workdir, f"{p['id']}.mp3")
            t0 = time.time()
            if engine == "kokoro":
                synth_kokoro(segs, voice, out)
            else:
                synth_google(segs, voice, key, out, workdir, p["id"])
            url = upload(out)
            p["audio"] = {"url": url, "seconds": duration(out), "bytes": os.path.getsize(out), "voice": tag}
            updates[p["id"]] = p["audio"]
            done += 1
            print(f"  {p['id']}: {p['audio']['seconds']} s, {p['audio']['bytes'] // 1024} KB, {time.time() - t0:.0f} s to make", flush=True)
        except Exception as e:  # keep going; the next run retries this post
            failed.append(f"{p['id']}: {e}")
            print(f"  {p['id']}: FAILED {e}", flush=True)
        if done and done % 10 == 0:
            json.dump(data, open(path, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
            json.dump(updates, open("audio-updates.json", "w", encoding="utf-8"), indent=1)
    if done:
        json.dump(data, open(path, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
        json.dump(updates, open("audio-updates.json", "w", encoding="utf-8"), indent=1)
    print(f"synthesized {done}, failed {len(failed)}, {total_chars} characters, {(time.time() - started) / 60:.0f} min")
    for f in failed[:20]:
        print("  " + f)


if __name__ == "__main__":
    main()
