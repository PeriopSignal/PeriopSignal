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
Actions tab → **iOS release (TestFlight)** → *Run workflow* → version (e.g. `1.0.0`). About 15 minutes later the build appears under the app's **TestFlight** tab in App Store Connect (Apple's processing adds 5–20 minutes). Each run gets a new build number automatically.

## 6. Invite colleagues (TestFlight)
1. App Store Connect → your app → **TestFlight** → the build → complete the short **Test Information** (what to test, contact email).
2. **External Testing** → **+** group, e.g. `Colleagues` → enable **Public link** → copy the link. The first build in a group goes through a brief Beta App Review (usually a day).
3. Colleagues install **TestFlight** from the App Store and open the link. Up to 10,000 testers; builds expire after 90 days, so run step 5 at least every three months (any code change or none).

## 7. Morning push notifications (optional, 10 minutes)
Without this, the app still alerts through background refresh (iOS decides the timing, usually within a few hours). With it, everyone gets one push a few minutes after the daily run publishes.
1. https://console.firebase.google.com → **Add project** → name `Periop Signal` (Analytics off).
2. In the project, add an **iOS app** with bundle ID `org.periopsignal.app`; download **GoogleService-Info.plist**.
3. **Project settings** → **Cloud Messaging** → **Apple app configuration** → upload an **APNs Authentication Key**: create it at https://developer.apple.com/account/resources/authkeys/list (**+**, tick *Apple Push Notifications service*), download the .p8, and enter its Key ID and your Team ID.
4. **Project settings** → **Service accounts** → **Generate new private key** (a JSON file).
5. Add two more repository secrets: `FIREBASE_PLIST_B64` = the plist file base64-encoded (on any computer: `base64 -i GoogleService-Info.plist` on macOS, `certutil -encode` on Windows, or paste the file into an online base64 encoder), and `FIREBASE_SERVICE_ACCOUNT` = the full JSON text.
6. Run step 5 again. New builds include Firebase; the `Notify app users of new posts` workflow sends the push each time posts.json changes.

## Troubleshooting
- The workflow writes its logs to the `ci-results` branch of the repository (folder `results/`), which Claude can read for you.
- "No app record found" during upload: do step 4.
- Cloud-signing errors: confirm the API key role is **Admin** and `APPLE_TEAM_ID` is the 10-character Team ID.
