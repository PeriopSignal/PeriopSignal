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
- **Reference tab**: calculators (RCRI, ARISCAT, STOP-Bang, modified Aldrete, Apfel, pediatric weight-based doses with tube sizes, fluids and blood volume), quick references condensed from society documents (ASRA anticoagulation, ASE valve severity criteria, ACC/AHA valve intervention recommendations, ASA fasting, ASA difficult airway, ASRA LAST and MHAUS malignant hyperthermia checklists, PONV consensus), then every guideline and consensus statement from the feed by society, then FDA and safety notices. The quick references and the pediatric table are `reference.json` at the repository root, checked by `tools/validate_reference.py`; the app refreshes it on launch, so a correction there reaches phones without an app update. Each calculator's arithmetic is unit-tested (`ios/Tests/ReferenceTests.swift`).
- **Ask**: when a search finds nothing (or next to its results), the question can be answered by AI with the best-matching posts and references as context and the sources listed: on the phone with Apple Intelligence (iPhone 15 Pro or newer, iOS 26), otherwise by Claude through a small proxy you host (section 10). Until the proxy exists, only the on-device route shows.
- **Cite**: AMA citation, DOI, BibTeX or a RIS file for EndNote, Zotero, Mendeley and Papers, from the Crossref record the `Citations` workflow fills in daily at 10:15 UTC (`citation` in `posts.json`).
- **Share as image**: a card with the headline, three take-home points and a QR code to the post.
- **More tab**: your topics (the feed gets a *For you* filter and alerts only cover those topics), earliest alert time, quiet weekends, Sunday digest, theme, text size, listening speed.
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
