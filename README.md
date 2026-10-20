# Periop Signal

A curated research feed for cardiothoracic, critical care and trauma anesthesiology. Short posts with take-home points, a direct link to each paper, and a longer AI-written overview. Published as a static site on GitHub Pages and updated every morning by a scheduled Claude task.

## Files

| Path | What it is |
|---|---|
| `index.html` | The site. **Generated** from `src/page.html`; do not edit directly. |
| `posts.json` | The feed data. One object per post, newest first. `takeHome` holds the authors' own key points when `takeHomeBy` is `authors` (otherwise an editorial take-home, kept where the readable abstract was too generic); `authorLimitations` the limitations they state; `authorBasis` what was read (full text, abstract, summary page); `editorTakeHome` keeps the earlier editorial bullets and is not displayed. Updated by the daily and weekly runs. |
| `inbox.txt` | Paste a DOI or link here (one per line) and the next run writes the post. |
| `log/` | One triage log per run: what each journal published, what was posted, what was rejected and why. |
| `feed.xml` | RSS feed, newest 50 posts. Generated. |
| `manifest.webmanifest`, `icons/` | App icon and "Add to Home Screen" support. Generated. |
| `src/page.html` | Page source, shared with the Claude artifact copy of the feed. |
| `tools/build_site.py` | Builds `index.html`, `manifest.webmanifest` and `feed.xml`. |
| `tools/make_icons.js` | Regenerates the icons and social preview image (needs the `sharp` npm package). |

## Daily update

A scheduled task searches the major journals, society pages and FDA notices, writes any posts that clear the quality bar, prepends them to `posts.json`, rebuilds `feed.xml`, and pushes to `main`. GitHub Pages redeploys automatically.

To rebuild by hand after editing `src/page.html` or `posts.json`:

```
python3 -I tools/build_site.py --base-url https://<user>.github.io/periop-signal/
```

## Post schema

```json
{
  "id": "nejm-2026-example", "date": "2026-10-14", "dateApprox": false, "addedAt": "2026-10-15",
  "journal": "NEJM", "jshort": "NEJM", "kind": "RCT",
  "topics": ["criticalCare"],
  "headline": "States the finding in <= 120 characters",
  "summary": "One or two plain sentences.",
  "takeHome": ["Bullet one", "Bullet two"], "takeHomeBy": "authors",
  "authorLimitations": ["Limitation the authors state"], "authorBasis": "abstract",
  "deepDive": "180-300 words of markdown (**bold**, '- ' bullets, blank-line paragraphs).",
  "url": "https://doi.org/...", "impact": 2, "trialName": "ACRONYM", "firstAuthor": "Surname"
}
```

Topics: `cardiac`, `cardiacSurgery`, `mcs`, `echo`, `thoracic`, `regional`, `ob`, `trauma`, `pediatric`, `pedsCardiac`, `liver`, `criticalCare`, `general`. Impact: 3 landmark, 2 important, 1 notable.

Summaries are AI-generated reading aids, not clinical advice. Read the source before acting on it.
