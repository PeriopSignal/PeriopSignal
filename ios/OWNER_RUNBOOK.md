# Periop Signal on iPhone: owner's runbook

No Mac needed. GitHub's macOS machines build the app; Apple signs it in the cloud; TestFlight distributes it.

## 1. Apple Developer Program (one time, 1–2 days)
1. Go to https://developer.apple.com/programs/enroll/ and enroll as an **individual** ($99/year). Use the Apple ID you want to own the app.
2. Wait for the approval email.

## 2. App Store Connect API key (one time, 5 minutes)
1. Sign in at https://appstoreconnect.apple.com → **Users and Access** → **Integrations** → **App Store Connect API** → **Team Keys** → **+**.
2. Name: `GitHub Actions`. Access: **Admin** (cloud signing needs it). Generate.
3. Note the **Issuer ID** (top of the page) and the key's **Key ID**, and **download the .p8 file** (it can only be downloaded once). Open it in a text editor; you will paste its whole content, including the BEGIN/END lines.
4. Your **Team ID** is at https://developer.apple.com/account → Membership details (10 characters).

## 3. Repository secrets (one time, 5 minutes)
At https://github.com/PeriopSignal/PeriopSignal/settings/secrets/actions add:

| Secret | Value |
|---|---|
| `ASC_KEY_ID` | the Key ID |
| `ASC_ISSUER_ID` | the Issuer ID |
| `ASC_KEY_P8` | the full text of the .p8 file |
| `APPLE_TEAM_ID` | your Team ID |

## 4. Create the app record (one time, 3 minutes)
Run the **iOS release (TestFlight)** workflow once first (Actions tab → *iOS release (TestFlight)* → *Run workflow*); its first step registers the bundle identifiers `org.periopsignal.app` and `org.periopsignal.app.widget` in your account. The upload step will fail until the app record exists, which is expected on this first run. Then:
1. App Store Connect → **My Apps** → **+** → **New App**.
2. Platform iOS, Name `Periop Signal`, Primary language English (U.S.), Bundle ID `org.periopsignal.app`, SKU `periopsignal`. Full Access.

## 5. Build and upload (every release, 1 click)
Actions tab → **iOS release (TestFlight)** → *Run workflow* → version (e.g. `1.0.0`), optionally *What to test* text. About 15 minutes later the build is uploaded; a second job then waits for Apple's processing (5–20 minutes), submits the build for Beta App Review and adds it to the **Colleagues** TestFlight group, so testers get it without anyone opening App Store Connect. Each run gets a new build number automatically. Leave the *group* input blank to upload without distributing.

## 6. Invite colleagues (TestFlight)
Done once (October 2026): the external group **Colleagues** exists with a **public link**, which is under App Store Connect → TestFlight → Colleagues. Colleagues install **TestFlight** from the App Store and open the link; every later release reaches them automatically (step 5).
- Up to 10,000 testers per public link; the first build in the group went through Beta App Review, later ones usually clear within hours.
- Builds expire after 90 days, so ship a release at least every three months (any code change or none).
- To put an existing build in the group by hand (or after a failed distribution): Actions → **TestFlight distribute** → version and build number.

## 7. Morning push notifications (optional, 10 minutes)
Without this, the app still alerts through background refresh (iOS decides the timing, usually within a few hours; the app holds the alert until the reader's chosen time and respects quiet weekends). With it, everyone gets one push at 06:31 Eastern (the `Notify app users of new posts` workflow runs hourly from 06:31 to 12:31 and sends whatever the morning run added, per topic, plus a Sunday digest at 09:31).
1. https://console.firebase.google.com → **Add project** → name `Periop Signal` (Analytics off).
2. In the project, add an **iOS app** with bundle ID `org.periopsignal.app`; download **GoogleService-Info.plist**.
3. **Project settings** → **Cloud Messaging** → **Apple app configuration** → upload an **APNs Authentication Key**: create it at https://developer.apple.com/account/resources/authkeys/list (**+**, tick *Apple Push Notifications service*), download the .p8, and enter its Key ID and your Team ID.
4. **Project settings** → **Service accounts** → **Generate new private key** (a JSON file).
5. Add two more repository secrets: `FIREBASE_PLIST_B64` = the plist file base64-encoded (on any computer: `base64 -i GoogleService-Info.plist` on macOS, `certutil -encode` on Windows, or paste the file into an online base64 encoder), and `FIREBASE_SERVICE_ACCOUNT` = the full JSON text.
6. Run step 5 again. New builds include Firebase and subscribe each reader to the topics they chose (`t-cardiac`, …, or `new-posts` when they follow everything, `-weekdays` variants for quiet weekends, and `weekly-digest`). To check the sender without waiting for a morning: Actions → *Notify app users of new posts* → *Run workflow* with `test_message` = true (one test push to `new-posts`), or `dry_run` = true to see what a real run would send.

## 8. What the app does with the feed
- **Today card**: new and unread counts, *Start reading*, *Listen* (reads the posts aloud; works with the screen locked and from the lock-screen controls), *Mark all read*. The app icon badge counts unread posts from the last two weeks.
- **Question of the day**: one board-style question from a recent post, with a streak. Questions live in `posts.json` (`quiz`), written by the morning run and checked by `tools/validate_posts.py`.
- **At a glance**: design, population, primary outcome and result on research posts (`glance` in `posts.json`).
- **Terms on first launch**: a one-time screen (for licensed clinicians; a reference aid that does not replace judgment or protocols; not reviewed or cleared by the FDA; no identifiers in My Patient) that must be accepted before the app opens; the full terms and the privacy notes are under More → Terms and privacy. Changing `Terms.version` in `ios/Shared/Terms.swift` asks everyone to accept again. Screenshot runs skip it unless `-ps.terms show`.
- **My Patient tab** (between Feed and Reference): one patient at a time, as a short preanesthetic note: age, sex, height and weight (BMI, BSA, ideal and lean body weight worked out), the procedure and its timing (elective, time-sensitive, urgent or emergency, as the 2024 AHA/ACC guideline defines them), problems by system with free text for anything rare, medications and allergies (flagged drugs show the 2024 AHA/ACC advice, such as holding an SGLT2 inhibitor 3 to 4 days), anesthesia history, last intake and labs (including BNP and NT-proBNP); a suggested ASA class from the ASA's own examples, shown as a table of what matched, for the clinician to confirm (with E), METs and the Duke Activity Status Index (34 or less is poor), frailty, cardiac symptoms, the stepwise 2024 AHA/ACC cardiac evaluation (box by box as the guideline's Figure 1 draws it, with its ECG, echo and consultation advice), and the risk scores to run; the airway exam (original Mallampati drawings to tap, the ASA examination's difficult-airway signs, and the Langeron and Kheterpal mask-ventilation predictors worked out from the record); the intraoperative record (mask ventilation with the Han grade, supraglottic airway and intubation, device, view and attempts, the ASA's follow-up after a difficult airway, lines, blocks, infusions, fluids and blood, events or "no notable events", echo findings); the plan (disposition, pain, when to call, to-dos); and **Generate Handoff**, which writes it up as text to copy or share. The record stays on the phone in a protected file (unreadable while locked, excluded from iCloud and computer backups, never sent anywhere) with no name, record number or date of birth, until the trash button clears it (Undo brings it back until the next edit). The calculators take age, sex, height and weight from it as one "From My Patient" line that can be changed, and the RCRI, ARISCAT, STOP-Bang and Apfel open with the answers the record already gives, then save their result back to it.
- **Reference tab**: seven folders, built as guides rather than reading material: the user enters what they have and the tool gives the answer, with a button to the underlying tables and a link to the society document. Tools that need a weight show a "Required" field until it is entered; outside My Patient the weight (and a child's age) is never saved and clears when the tool is closed.
  - *Emergency*: the ACLS code timer (adult, child and post-cardiac-surgery arrest, tachycardia, bradycardia, anaphylaxis: a running clock, CPR cycles, drug timers and prompts, an event log to copy); OB Emergencies (13 checklists built from the primary sources, from maternal arrest with its 4- and 5-minute delivery clock to hemorrhage, eclampsia, high block, amniotic fluid embolism, failed intubation, LAST, sepsis, cord prolapse, rupture, dystocia, inversion and newborn resuscitation with its own weight; the Stanford manual is linked, not copied); local anesthetic toxicity and malignant hyperthermia as numbered checklists (progress count, reset) that compute the weight-based doses; the difficult-airway guide (assessment in, plan out, attempt counter, cannot-ventilate checklist).
  - *Preoperative*: RCRI, ARISCAT, STOP-Bang; fasting (what was taken and when → earliest start).
  - *Cardiothoracic*: ASE valve severity grading (echo measurements and signs → the ASE grade and its pathway); AHA/ACC valve intervention (the 2020 guideline as prompted questions); ASE chamber quantification (sex, height and weight → BSA; LV, LA, RV size and function, RA, tricuspid annulus and aortic sinuses graded normal / mild / moderate / severe or normal / abnormal against Lang 2015, the ASE 2025 right-heart guideline, ASE 2017 and the 2015 aorta guideline, each row with its cutoffs as a strip; rows with indexed cutoffs grade both; RA pressure from the IVC, including on positive-pressure ventilation); ASE diastolic function (the 2025 algorithm: e′, E/e′ and PASP or TR first, the supplemental and second-line signs when they disagree, E/A for the grade; annular calcification, transplant and the special populations; it states the guideline's own limit that it is not for the intraoperative setting).
  - *General Anesthesia*: PONV (Apfel factors → how many antiemetics, the agents to tick, rescue limited to classes not yet given); modified Aldrete.
  - *Regional*: the technique finder (mark the incision on a body figure → the neuraxial level and the blocks for each area), 26 peripheral nerve blocks with original schematics, volumes and NYSORA links, and the neuraxial guide (procedure → level, drugs and doses); blocks on anticoagulants (drug, dose, kidney function, last dose → earliest block, catheter policy, next dose; ASRA 5th edition); local anesthetic calculator (weight and the volumes of each agent; the total turns red above the label maximum; mixtures and Exparel's rules).
  - *General Anesthesia* also holds the arterial blood gas interpretation (primary disorder, compensation, anion gap and delta, the A–a gradient).
  - *Medications & Hematology*: opens straight to the drug list (a folder with one tool opens the tool; Pediatrics too). Tabs for hemodynamic infusions (vasopressors, inotropes, vasodilators and antihypertensives, pulmonary vasodilators), single-dose medications, anesthetic and other infusions, blood products (the transfusion threshold on each row) and hematologic drugs (factor concentrates, antifibrinolytics and hemostatics, anticoagulants, reversal agents). Each row is the drug and its starting dose, with the per-kg or per-minute equivalent once a weight is entered; tap for the indication, titration, range, maximum, preparation, cautions and source.
  - *Pediatrics*: weight-based doses, tube sizes, fluids and blood volume; the local anesthetic link passes the child's weight and age along.
  - **Favorites**: the star in a tool's toolbar, or a long-press on its tile, pins it to the top of the tab; the list syncs through iCloud like saved posts.
  - The content behind the tools (quick references, pediatric drugs, local anesthetic labels, infusion doses, anticoagulation rules, echo reference values and the diastolic populations) is `reference.json` at the repository root, checked by `tools/validate_reference.py`; the app and the website refresh it on launch, so a correction there reaches phones without an app update. Every calculator's arithmetic and every grading rule is unit-tested (`ios/Tests/ReferenceTests.swift`), and the CI run screenshots each tool (`results/build/shots` on the `ci-results` branch).
  - Links: `periopsignal://tool/valves`, `periopsignal://score/rcri`, `periopsignal://ref/asra-last` open a tool, score or card directly.
  - **On the website** the same Reference tab sits beside the feed (the *Reference* button under the header): every folder, calculator and guided tool, favorites (kept in that browser), search across tools, quick references and posts, and links such as `#tool-chamber`, `#folder-cardiothoracic` or `#card-asra-last`. The site also has Listen, the question of the day with its streak, the quiz in each deep dive and Cite; push alerts, the widget, iCloud sync and Ask stay in the app. The page is built from `src/page.html` with `src/reference-logic.js` (the shared arithmetic, tested by `node tools/test_reference_logic.js`), `src/reference-ui.js`, `src/reference-echo.js` and `src/reference.css` by `tools/build_site.py`.
- **Ask**: when a search finds nothing (or next to its results), the question can be answered by AI with the best-matching posts and references as context and the sources listed: on the phone with Apple Intelligence (iPhone 15 Pro or newer, iOS 26), otherwise by Claude through a small proxy you host (section 10). Until the proxy exists, only the on-device route shows.
- **Cite**: AMA citation, DOI, BibTeX or a RIS file for EndNote, Zotero, Mendeley and Papers, from the Crossref record the `Citations` workflow fills in daily at 10:15 UTC (`citation` in `posts.json`).
- **Share as image**: a card with the headline, three take-home points and a QR code to the post.
- **More tab**: saved posts (moved here from the tab bar), your topics (the feed gets a *For you* filter and alerts only cover those topics), earliest alert time, quiet weekends, Sunday digest, theme, text size, listening speed.
- Spotlight on the iPhone finds posts by trial name, drug or journal.

## 9. Natural voice for Listen (nothing to set up)
Every post gets a recording made by **Kokoro**, an open-weights neural voice that runs on GitHub's own machines: no account, no key, no cost. The `Post audio` workflow records new posts a few minutes after each morning update, keeps the MP3s in the repository's `audio` release, and the app streams them (downloaded once, then offline). Posts without a recording yet are read by the iPhone's own voice; for a better phone voice, download a free **Premium** one under iOS Settings → Accessibility → Spoken Content → Voices → English (Ava, Zoe, Evan) and pick it under More → Reading.

- **Change the voice**: add a repository **variable** `TTS_VOICE` (Settings → Secrets and variables → Actions → Variables), e.g. `af_bella`, `am_michael`, `bf_emma`, `bm_george` (list: https://huggingface.co/hexgrad/Kokoro-82M/blob/main/VOICES.md; the default `af_heart` is the best rated), then Actions → **Post audio** → *Run workflow* with `all` = true. About 70 posts are re-recorded per run; run it again until the summary says 0 pending.
- **Google's voice instead** (optional, free up to 1M characters a month; needs a Google Cloud project with billing linked): enable *Cloud Text-to-Speech API*, create an API key restricted to it, add the secret `GOOGLE_TTS_API_KEY` and the variable `TTS_ENGINE` = `google` (`TTS_VOICE` e.g. `en-US-Chirp3-HD-Charon`), then run the workflow with `all` = true.

## 10. Answers by Claude (optional, 10 minutes)
The app never holds an API key; a tiny Cloudflare Worker (`worker/`) does, and the workflow **Ask worker (deploy)** publishes it.
1. **Anthropic key**: https://console.anthropic.com → API keys → create one; under Settings → Limits set a monthly spend cap you are comfortable with (a question costs a fraction of a cent; a busy month is a few dollars).
2. **Cloudflare** (free plan): sign up at https://dash.cloudflare.com → the *Account ID* is on the account overview page; then My Profile → API Tokens → *Create Token* → template **Edit Cloudflare Workers** → create and copy it.
3. Add three repository secrets (Settings → Secrets and variables → Actions): `ANTHROPIC_API_KEY`, `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID`.
4. Actions → **Ask worker (deploy)** → *Run workflow*. It deploys, checks the worker answers, and records its address in `reference.json`; the app picks it up at its next launch. Phones with Apple Intelligence keep answering on the device unless the switch under More → Answers is turned off.
- Model: `MODEL` in `worker/wrangler.toml` (default `claude-sonnet-5-5`). Rate limit: 30 questions a minute per address, set in the same file.
- To stop it: delete the Worker in the Cloudflare dashboard, or remove `ask.endpoint` from `reference.json`.

## Troubleshooting
- The workflow writes its logs to the `ci-results` branch of the repository (folder `results/`), which Claude can read for you.
- The notification sender keeps what it has already sent in `results/notify/state.json` on the same branch; delete that file to make it treat everything as already sent on its next run.
- A build or release that sits "queued" for 15 minutes and ends "cancelled" with *The job was not acquired by Runner* means GitHub's macOS pool for that runner label ran out of capacity (it posts a notice about arm64 runners). The iOS workflows run on `macos-15-intel`, a separate pool, for that reason; `macos-15` (Apple silicon) is a little faster when it is available — change `runs-on` in `.github/workflows/ios-build.yml` and `ios-release.yml` to switch.
- "No app record found" during upload: do step 4.
- The *TestFlight group* job says "No TestFlight group named 'Colleagues'": the group was renamed or deleted; recreate it under TestFlight → External Testing, or run the release with the new name in the *group* input.
- "beta app review not submitted": Test Information (beta description, contact email) is missing under TestFlight → Test Information; fill it in, then run **TestFlight distribute** for that build.
- Cloud-signing errors: confirm the API key role is **Admin** and `APPLE_TEAM_ID` is the 10-character Team ID.
