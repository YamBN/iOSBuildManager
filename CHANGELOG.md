# Changelog

The source of truth for the app version is `iOSBuildManager/iOSBuildManager/Models/AppVersion.swift`.
`Info.plist` (`CFBundleShortVersionString`) and the Xcode build settings
(`MARKETING_VERSION`, `CURRENT_PROJECT_VERSION`) are kept in sync. The in-app
About / Settings screens show the latest 3 entries below.

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
