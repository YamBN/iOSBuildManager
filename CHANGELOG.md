# Changelog

The source of truth for the app version is `iOSBuildManager/iOSBuildManager/Models/AppVersion.swift`.
`Info.plist` (`CFBundleShortVersionString`) and the Xcode build settings
(`MARKETING_VERSION`, `CURRENT_PROJECT_VERSION`) are kept in sync. The in-app
About / Settings screens show the latest 3 entries below.

## 1.2.0 — 2026-07-09

- Checks GitHub Releases on launch and shows an **Update Available** sheet
  with release notes when a newer version exists — one unauthenticated,
  telemetry-free request to `api.github.com`. Toggle in Settings → Advanced
  → About, plus a **Check for Updates Now** button; "Skip This Version" is
  remembered.
- Fixed: the **sidebar rendered flat gray** instead of the same navy glass
  gradient as the rest of the app — `detailView` had its own `AppBackground`
  but the sidebar was only inheriting the outer one, which macOS's automatic
  sidebar vibrancy material was blocking. Gave the sidebar its own background.
- README: clearer, version-specific steps for opening the ad-hoc-signed app
  past Gatekeeper (the one-liner `xattr -cr`, and the macOS Sequoia+ System
  Settings path since right-click → Open no longer offers a bypass there).

## 1.1.0 — 2026-07-08

- Flexible scheduled builds: **Every N days**, **Daily** at a set time, or
  **Weekly** on chosen weekdays at a set time (launchd `StartCalendarInterval`).
- The app now keeps running in the **menu bar** after you close its window
  (no Dock icon), so scheduled builds and quick actions stay available.
- New guide: [keeping sideloaded apps alive with no computer](docs/iphone-auto-refresh.md)
  — an on-iPhone SideStore + Shortcuts automation.

## 1.0.0 — 2026-07-08

First public release.

- Dashboard with Latest Build, Build Status, Quick Actions, and Recent Builds
- Build any `.xcodeproj` / `.xcworkspace` with live log streaming
- Automatic IPA packaging (`Payload/App.app` → zip) with versioned names + `latest.ipa`
- iCloud Drive output folder for SideStore / AltStore / Sideloadly installs
- Provisioning profile manager (scan, import, expiry status)
- Signing certificate manager (keychain scan, import, expiry status)
- Signing-expiry warning banner on the dashboard (free-Apple-ID 7-day cycle)
- Install on device via `devicectl`
- Scheduled builds (LaunchAgent) with automatic device re-install + notification
- macOS notifications on build success/failure
- Xcode Run Script integration (package after build, no build loops)
- Dark / Light / System themes; local-only, no analytics
