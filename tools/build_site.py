#!/usr/bin/env python3
"""Build the standalone website from the shared page source.

  src/page.html  ->  index.html   (full HTML document for GitHub Pages)
  posts.json     ->  feed.xml     (RSS 2.0, newest 50 posts)
  manifest.webmanifest is written from the constants below.

Usage:  python3 -I tools/build_site.py [--base-url https://user.github.io/periop-signal/]
The base URL only matters for absolute links in feed.xml and the social preview tags.
"""
import argparse, datetime, html, json, os, re, sys
from xml.sax.saxutils import escape

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NAME = "Periop Signal"
DESCRIPTION = ("A curated research feed for cardiothoracic, critical care and trauma anesthesiology: "
               "landmark trials, guidelines and regulatory news, with take-home points, paper links and AI overviews.")
THEME_DARK = "#0A0E14"
THEME_LIGHT = "#F3F5F9"
ACCENT = "#F2634F"


def read(p):
    with open(os.path.join(ROOT, p), encoding="utf-8") as fh:
        return fh.read()


def write(p, s):
    with open(os.path.join(ROOT, p), "w", encoding="utf-8") as fh:
        fh.write(s)


def build_index(base_url):
    page = read("src/page.html")
    # lift the <title>, drop the artifact-only meta line
    m = re.search(r"<title>(.*?)</title>\s*", page, re.S)
    title = html.unescape(m.group(1).strip()) if m else NAME
    page = page.replace(m.group(0), "", 1) if m else page
    page = re.sub(r'<meta name="claude:viewport-fit-sides"[^>]*>\s*', "", page)
    og_image = (base_url.rstrip("/") + "/icons/og.png") if base_url else ""
    canonical = f'<link rel="canonical" href="{html.escape(base_url)}">\n' if base_url else ""
    og_img_tag = f'<meta property="og:image" content="{html.escape(og_image)}">\n<meta name="twitter:card" content="summary_large_image">\n' if og_image else '<meta name="twitter:card" content="summary">\n'
    head = f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<title>{html.escape(title)}</title>
<meta name="description" content="{html.escape(DESCRIPTION)}">
<meta name="color-scheme" content="dark light">
<meta name="theme-color" content="{THEME_DARK}">
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
<meta name="apple-mobile-web-app-title" content="{html.escape(NAME)}">
<meta property="og:type" content="website">
<meta property="og:site_name" content="{html.escape(NAME)}">
<meta property="og:title" content="{html.escape(title)}">
<meta property="og:description" content="{html.escape(DESCRIPTION)}">
{og_img_tag}{canonical}<link rel="manifest" href="manifest.webmanifest">
<link rel="icon" href="icons/icon.svg" type="image/svg+xml">
<link rel="icon" href="icons/icon-192.png" type="image/png" sizes="192x192">
<link rel="apple-touch-icon" href="icons/apple-touch-icon.png">
<link rel="alternate" type="application/rss+xml" title="{html.escape(NAME)}" href="feed.xml">
<style>
:root {{ padding-top: env(safe-area-inset-top, 0px); padding-bottom: env(safe-area-inset-bottom, 0px); }}
body {{ margin: 0; font: 14px system-ui, sans-serif; background: #0A0E14; }}
img {{ max-width: 100%; }}
[hidden] {{ display: none !important; }}
</style>
</head>
<body>
"""
    write("index.html", head + page.strip() + "\n</body>\n</html>\n")
    return title


def build_manifest():
    manifest = {
        "name": NAME, "short_name": NAME, "description": DESCRIPTION,
        "start_url": "./", "scope": "./", "display": "standalone", "orientation": "portrait",
        "background_color": THEME_DARK, "theme_color": THEME_DARK,
        "icons": [
            {"src": "icons/icon-192.png", "sizes": "192x192", "type": "image/png"},
            {"src": "icons/icon-512.png", "sizes": "512x512", "type": "image/png"},
            {"src": "icons/icon-maskable-512.png", "sizes": "512x512", "type": "image/png", "purpose": "maskable"},
        ],
    }
    write("manifest.webmanifest", json.dumps(manifest, indent=1) + "\n")


def md_to_html(src):
    """Same tiny markdown subset the page renders: **bold**, '- ' bullets, blank-line paragraphs."""
    out, para, items = [], [], []
    inline = lambda t: re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", escape(t))
    def flush_p():
        if para: out.append("<p>" + inline(" ".join(para)) + "</p>"); para.clear()
    def flush_l():
        if items: out.append("<ul>" + "".join("<li>" + inline(i) + "</li>" for i in items) + "</ul>"); items.clear()
    for raw in src.split("\n"):
        l = raw.strip()
        if not l: flush_p(); flush_l(); continue
        if re.match(r"^[-*•]\s+", l): flush_p(); items.append(re.sub(r"^[-*•]\s+", "", l)); continue
        flush_l(); para.append(l)
    flush_p(); flush_l()
    return "".join(out)


def build_rss(base_url, limit=50):
    data = json.load(open(os.path.join(ROOT, "posts.json"), encoding="utf-8"))
    posts = sorted(data["posts"], key=lambda p: (p["addedAt"], p["date"]), reverse=True)[:limit]
    site = base_url.rstrip("/") + "/" if base_url else ""
    def rfc822(d):
        y, m, dd = (int(x) for x in d.split("-"))
        return datetime.datetime(y, m, dd, 11, 0, tzinfo=datetime.timezone.utc).strftime("%a, %d %b %Y %H:%M:%S +0000")
    items = []
    for p in posts:
        link = f"{site}#{p['id']}" if site else p["url"]
        body = (f"<p><em>{escape(p['journal'])} · {escape(p['kind'])} · {escape(p['date'])}</em></p>"
                f"<p>{escape(p['summary'])}</p><p><strong>Take-home</strong></p><ul>"
                + "".join(f"<li>{escape(b)}</li>" for b in p["takeHome"]) + "</ul>"
                + md_to_html(p["deepDive"])
                + f"<p><a href=\"{escape(p['url'])}\">Open the paper</a></p>")
        cats = "".join(f"<category>{escape(t)}</category>" for t in p["topics"])
        items.append(f"""  <item>
   <title>{escape(p['headline'])}</title>
   <link>{escape(link)}</link>
   <guid isPermaLink="false">periop-signal:{escape(p['id'])}</guid>
   <pubDate>{rfc822(p['addedAt'])}</pubDate>
   {cats}
   <description>{escape(body)}</description>
  </item>""")
    now = datetime.datetime.now(datetime.timezone.utc).strftime("%a, %d %b %Y %H:%M:%S +0000")
    xml = f"""<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom">
 <channel>
  <title>{escape(NAME)}</title>
  <link>{escape(site or 'https://example.invalid/')}</link>
  <description>{escape(DESCRIPTION)}</description>
  <language>en-us</language>
  <lastBuildDate>{now}</lastBuildDate>
  {f'<atom:link href="{escape(site)}feed.xml" rel="self" type="application/rss+xml"/>' if site else ''}
{chr(10).join(items)}
 </channel>
</rss>
"""
    write("feed.xml", xml)
    return len(posts)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base-url", default=os.environ.get("PERIOP_BASE_URL", ""))
    a = ap.parse_args()
    title = build_index(a.base_url)
    build_manifest()
    n = build_rss(a.base_url)
    print(f"built index.html ({title}), manifest.webmanifest, feed.xml ({n} items); base_url={a.base_url or '(none)'}")


if __name__ == "__main__":
    main()
