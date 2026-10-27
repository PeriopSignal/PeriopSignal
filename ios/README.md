# Periop Signal for iPhone

A native SwiftUI app for the feed at https://periopsignal.github.io/PeriopSignal/. It reads the same `posts.json`, caches it for offline reading, syncs saved posts through iCloud, ships a home/lock-screen widget with the latest landmark paper, and notifies when new papers land.

The Xcode project is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen); nothing in here needs a Mac to maintain. GitHub Actions builds, tests and screenshots the app on every change (`.github/workflows/ios-build.yml`) and `ios-release.yml` archives and uploads to TestFlight.

## Layout

| Path | What |
|---|---|
| `Shared/` | Model (`Post`, `Feed`), feed loader and cache, theme tokens, logo mark. Compiled into the app and the widget. |
| `PeriopSignal/App` | App entry, router (deep links `periopsignal://post/<id>`), app delegate (notifications, background refresh). |
| `PeriopSignal/Store` | `PostStore` (filters, related posts, guideline groups), `SavedStore` and `ReadStore` (iCloud key-value), `QuizStore` (question of the day, streak), `Preferences` (topics, alert time, text size), `SpeechPlayer` (listen, lock-screen controls), `SpotlightIndexer`, `Citations` (AMA, RIS, BibTeX), `NotificationManager`, `PushBridge` (Firebase topics, optional). |
| `PeriopSignal/Views` | Feed (Today card, question of the day, filters), cards, deep dive (glance strip, quiz, related, cite and share menus), Guidelines tab, saved list, More (settings), onboarding, share image, mini player. |
| `PeriopSignalWidget/` | WidgetKit extension. |
| `Tests/` | Decoding, citation, society, speech-text and quiz tests. |

## Notifications

Two layers. Background refresh posts a local notification when it finds new posts (no server), held until the reader's chosen time, skipped on quiet weekends, with a Sunday digest. When `GoogleService-Info.plist` is placed next to `Info.plist` and the Firebase package is added to `project.yml`, the app also subscribes to FCM topics: `new-posts` (readers following everything), `t-<topic>` for each chosen topic, and `weekly-digest`. The publishing workflow (`notify.yml`) sends one message per topic with a shared collapse id, so a reader gets one notification per update.

## Feed fields the app uses beyond the website

`glance` (design, population, outcome, result), `quiz` (one question, four options, answer index, explanation), `title` and `citation` (from Crossref). All optional; `tools/validate_posts.py` checks them.
