# Periop Signal for iPhone

A native SwiftUI app for the feed at https://periopsignal.github.io/PeriopSignal/. It reads the same `posts.json`, caches it for offline reading, syncs saved posts through iCloud, ships a home/lock-screen widget with the latest landmark paper, and notifies when new papers land.

The Xcode project is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen); nothing in here needs a Mac to maintain. GitHub Actions builds, tests and screenshots the app on every change (`.github/workflows/ios-build.yml`) and `ios-release.yml` archives and uploads to TestFlight.

## Layout

| Path | What |
|---|---|
| `Shared/` | Model (`Post`, `Feed`), feed loader and cache, theme tokens, logo mark. Compiled into the app and the widget. |
| `PeriopSignal/App` | App entry, router (deep links `periopsignal://post/<id>`), app delegate (notifications, background refresh). |
| `PeriopSignal/Store` | `PostStore` (filters, refresh), `SavedStore` (iCloud key-value), `NotificationManager`, `PushBridge` (Firebase, optional). |
| `PeriopSignal/Views` | Feed, cards, deep dive, saved list, about/settings. |
| `PeriopSignalWidget/` | WidgetKit extension. |
| `Tests/` | Decoding and markdown tests. |

## Notifications

Two layers. Background refresh posts a local notification when it finds new posts (no server). When `GoogleService-Info.plist` is placed next to `Info.plist` and the Firebase package is added to `project.yml`, the app also subscribes to the FCM topic `new-posts`, which the publishing workflow pings on every update.
