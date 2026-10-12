# Changelog

The source of truth for the app version is `iOSBuildManager/iOSBuildManager/Models/AppVersion.swift`.
`Info.plist` (`CFBundleShortVersionString`) and the Xcode build settings
(`MARKETING_VERSION`, `CURRENT_PROJECT_VERSION`) are kept in sync. The in-app
About / Settings screens show the latest 3 entries below.

## 1.8.0 — 2026-10-12

### Added

- A bundled, local `iosbuild.py` CLI for AI agents and scripts to submit builds,
  list projects, inspect queue/job status, wait for results, cancel queued jobs,
  and resume dispatch after an interrupted worker. No Computer Use or HTTP server
  is needed. See [usage and agent instructions](docs/automation-queue.md).
- One persistent queue shared by GUI, CLI, and scheduled builds, using the
  existing `BuildEngine`. A process lock permits only one worker, and each
  accepted request receives a durable ID and result.
- Request IDs prevent duplicate execution when a client retries a submission.
  Project/configuration/output settings are captured when a request is accepted.
- Separate output directories for every project and request, preventing IPA and
  `latest.ipa` collisions. Successful receipts provide the exact artifact path.
- Queue status, recent requests, failures, and artifact shortcuts in Builds.

### Changed

- App bundle version metadata now follows the Xcode build settings, matching
  the version displayed inside the app and in download filenames.

- Manual and scheduled builds now enter the same queue. Scheduled builds retain
  their cadence and optional connected-device installation.
- Rebuild cleanup runs only when its queued job starts. Menu-bar build actions
  can enqueue work while another build is active; Open Latest uses the selected
  project's build history.
- Pending requests survive app closure. Interrupted work is recorded explicitly
  and dispatch pauses until the user has checked for orphan build processes and
  explicitly resumes it. Corrupt state or persistence errors stop dispatch.
- Queued artifacts are retained rather than automatically deleted. Source files
  are read from the working tree when execution begins, not snapshotted; keep
  each checkout stable until its build completes.

### Verification

- Release build completed; 83 Swift tests and 4 CLI tests passed locally,
  including 24 concurrent CLI submissions, serialized dispatch, recovery,
  cancellation, duplicate prevention, and persistence failures.
- An end-to-end test exercised CLI → queue → Xcode → IPA packaging, continuing
  after an intentionally failed build and producing isolated artifacts from
  two iOS fixture projects.
- A live project build through the installed CLI completed, passed 62 artifact
  checks and strict signature verification, and retained the exported game pack
  unchanged. Apple's local iCloud metadata reported the artifact fully uploaded.
- Physical-iPhone installation and live UI acceptance were not tested by this
  update. Build success alone does not establish iCloud synchronization or
  device installation; upload status was checked separately in the live test.

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
