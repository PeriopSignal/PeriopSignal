# Periop Signal enumeration data

Written every morning by `.github/workflows/enumerate.yml` on the main branch (script: `tools/enumerate.py`).
This branch is force-pushed, so it always holds a single commit. The scheduled feed runs read `data.json`:

- `generatedAt`, `windowStart`, `days`: when it was collected and the Crossref window (created date).
- `journals`: per journal, the ISSNs tried, `status` (ok / failed), `detail`, `count` and `supplementAbstractsSkipped`
  (meeting-abstract supplements such as ESC Congress abstracts, left out of `items`).
- `items`: each journal article: `doi`, `title`, `journal`, `group`, `created`, `published`, `firstAuthor`,
  `noise` (corrections, replies, letters and similar), `abstract` with `abstractSource` (crossref / openalex / europepmc / semanticscholar),
  `pmid`, `pmcid`, `oa`, `oaUrl`, and `limitations` (sentences around "limitation" in open PMC full text).
- `pmcPending`: the same for posts listed in log/pmc-pending.txt, keyed by post id, with `status`
  (full text / not available / error).
- `societyPages`: per page, `url`, HTTP `status`, page `text` and `newLines` (not on the previous snapshot).
