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
| `tools/validate_posts.py` | Checks `posts.json` (required fields, allowed values, duplicates, and the optional `glance`, `quiz`, `title` and `citation` objects). The runs and the citation workflow run it before committing. |
| `tools/backfill_citations.py` | Fills `title` and `citation` from Crossref for DOI posts; run daily by `.github/workflows/citations.yml`. |
| `ios/` | The iPhone app (SwiftUI, built and shipped to TestFlight by GitHub Actions). See `ios/README.md` and `ios/OWNER_RUNBOOK.md`. |
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
  "url": "https://doi.org/...", "impact": 2, "trialName": "ACRONYM", "firstAuthor": "Surname",
  "title": "The paper's title as published",
  "glance": {"design": "Multicentre RCT, 13 US hospitals", "n": "3,959 adults with septic shock", "outcome": "28-day mortality", "result": "31.8% vs 33.0%, adjusted OR 0.98; no difference"},
  "quiz": {"question": "…?", "options": ["…", "…", "…", "…"], "answer": 2, "explanation": "…"},
  "citation": {"title": "…", "authors": ["Family IN"], "journal": "JAMA", "year": 2026, "volume": "336", "issue": "15", "pages": "1234-1245", "doi": "10.1001/…"}
}
```

The last four are optional and used by the iPhone app: `glance` (research kinds only; four strings of at most 90 characters, written only from what the paper states), `quiz` (impact 2 and 3; one single-best-answer question with four options, answerable from the post alone), `title` and `citation` (from Crossref, filled by the citation workflow). The website ignores them for now.

Topics: `cardiac`, `cardiacSurgery`, `mcs`, `echo`, `thoracic`, `regional`, `ob`, `trauma`, `pediatric`, `pedsCardiac`, `liver`, `criticalCare`, `general`. Impact: 3 landmark, 2 important, 1 notable.

Summaries are AI-generated reading aids, not clinical advice. Read the source before acting on it.

### Where the runs get their reading list

`.github/workflows/enumerate.yml` runs `tools/enumerate.py` every morning at 06:07 UTC (02:07 EDT, 01:07 EST), about two hours before the 04:06 feed run (GitHub often starts scheduled workflows late). It lists every journal article Crossref registered for the feed's journals in the last 21 days, adds abstracts and open-access ids from OpenAlex and author-stated limitations from open PMC full text, snapshots the society and FDA pages the runs check, and force-pushes the result as `data.json` to the `data` branch (one commit, so the branch never grows). The runs read that file first and enumerate through Crossref themselves only when it is missing or more than 30 hours old: a scheduled run with the repository attached cannot fetch API addresses it builds itself without someone approving each one.

### How the daily run reaches the website

One scheduled task maintains the feed, "Periop Signal daily + Sunday sweep": it runs every morning at 04:06 America/New_York, looks back 7 days, and on Sundays does the deeper 21-day sweep (including the pending full-text checks). It needs this repository attached to the task, or GitHub refuses its pushes with "not in this session's authorized repository set". The task created from chat could not get a repository attached in the app, so the feed runs on the task that already had one. `.claude/settings.json` asks those runs for maximum reasoning effort: `CLAUDE_CODE_EFFORT_LEVEL=max`, with `effortLevel: xhigh` (the highest level a settings file accepts) as the fallback; the app's task settings have no effort control.

The scheduled run commits to `main`. If GitHub refuses that push, it pushes the same commit to a `claude/feed-<date>-<daily|weekly>` branch instead, and `.github/workflows/merge-feed-branch.yml` merges it into `main`, deletes the branch and rebuilds the site. Every run also refreshes the Claude artifact mirror and records its status there: the mirror's `posts.json` carries a top-level `pipeline` object (run time, posts added, which push path worked or the exact error, and the triage log). That object is never committed here. When the previous run's push failed, the next run first carries that run's posts over from the mirror, so nothing is lost while pushes are failing and everything lands with the next push that works.
