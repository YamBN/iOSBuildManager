# iOS Build Manager

A native **macOS developer tool** for the free-Apple-ID sideloading workflow:
build an Xcode project, package the `.app` into an `.ipa`, and drop it into
iCloud Drive so **SideStore / AltStore / Sideloadly** can install it on your
iPhone — then keep it alive past the 7-day signing window with scheduled
rebuilds and automatic re-installs.

> Local-only. No analytics. No tracking. No network calls. MIT licensed.

![Dashboard — dark](docs/screenshot-dark.png)

<details>
<summary>Light mode</summary>

![Dashboard — light](docs/screenshot-light.png)

</details>

## Why

Free Apple ID signing expires every 7 days, after which sideloaded apps stop
launching. The usual fix is a manual treadmill: open Xcode, rebuild, repackage,
re-install. iOS Build Manager automates the whole loop:

**build → package IPA → upload to iCloud → re-install on device → notify you.**

No paid Apple Developer Program required. Nothing here bypasses Apple security —
the app builds and packages exactly what Xcode signs.

## Features

- **Dashboard** — latest build, live build status, quick actions, recent builds
- **One-click builds** of any `.xcodeproj` / `.xcworkspace`, with scheme
  detection (`xcodebuild -list`) and live log streaming
- **IPA packaging** — `Payload/App.app` → zip, versioned names
  (`MyApp-1.2.3-45.ipa`) plus an always-current `latest.ipa`
- **iCloud Drive output** (default `~/Library/Mobile Documents/…/iOS Builds`)
  so the IPA is reachable from your phone
- **Profiles** — scans installed provisioning profiles, shows team + expiry,
  imports `.mobileprovision` files
- **Certificates** — lists keychain signing identities with real expiry dates,
  imports `.p12` / `.cer`
- **Signing-expiry banner** — warns on the dashboard when a profile or
  certificate is about to expire, with a one-click rebuild
- **Install on device** — pushes the freshly built app to a connected iPhone
  via `devicectl`
- **Scheduled builds** — a LaunchAgent rebuilds every N days (default 6),
  re-installs on a connected device, and posts a macOS notification
- **Build notifications** — success/failure notifications for manual builds too
- **Codesign check** — verifies the app's signature before packaging and warns
  when an IPA won't be directly installable
- **Xcode Run Script helper** — package automatically after every Xcode build,
  with no build loops
- **macOS apps and Swift packages too** — the platform is detected from the
  scheme; Mac builds export as a drag-to-Applications `.dmg` or a zipped `.app`,
  and a folder with a `Package.swift` builds with `swift build`
- **Appearance** — give the app you're building its own icon and display name;
  they're written into the `.app` on the next build (and it's re-signed), so
  the app you install actually carries them
- **GitHub built in** — sign in via the browser or the GitHub CLI, then commit
  and push, publish a repository, watch Actions, and cut a release with your
  build attached: **[docs/github-integration.md](docs/github-integration.md)**
- **Dark / Light / System** themes

## Requirements

- macOS 13 (Ventura) or newer
- Full **Xcode** installed (the app shells out to `xcodebuild`):

  ```bash
  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
  ```

- iCloud Drive enabled (optional — any output folder works)

## Install

**Download a release** from the [Releases page](https://github.com/YamBN/iOSBuildManager/releases):

- **`iOSBuildManager-<version>.dmg`** — open it and drag **iOS Build Manager**
  into the **Applications** folder. The standard macOS install.
- **`iOSBuildManager-<version>.app.zip`** — unzip and double-click the app to
  run it directly, no install needed.

> **First launch on another Mac:** the app is ad-hoc signed with a free Apple ID
> — not notarized by Apple, which requires a paid $99/year Developer Program
> membership — so Gatekeeper blocks it the first time. This is normal for any
> app distributed outside the App Store without notarization. One-time fix,
> pick whichever is easiest:
>
> **Terminal (fastest, works on every macOS version):**
> ```bash
> xattr -cr /Applications/iOSBuildManager.app
> ```
>
> **macOS Sequoia (15) and newer** — right-click → Open no longer offers a
> bypass, so instead:
> 1. Try to open the app normally (you'll get a "can't be opened" alert).
> 2. **System Settings → Privacy & Security** → scroll down to the security
>    section — you'll see *"iOSBuildManager was blocked to protect your Mac"*
>    with an **Open Anyway** button. Click it, then confirm with your password.
>
> **macOS Sonoma (14) and older:**
> Right-click (or Control-click) the app → **Open** → **Open** in the dialog
> that appears.
>
> Any of these only has to be done once — macOS remembers your choice after that.

### Build it yourself

```bash
git clone https://github.com/YamBN/iOSBuildManager.git
cd iOSBuildManager
./scripts/make-dmg.sh          # → dist/iOSBuildManager-<version>.dmg + .app.zip
```

Or open `iOSBuildManager/iOSBuildManager.xcodeproj` in Xcode and hit ⌘R.

First run:

1. **Settings → General → Choose…** and pick your `.xcodeproj` / `.xcworkspace`
2. Pick a **scheme** and **configuration** (Release recommended)
3. **Settings → Build** — destination `Generic iOS Device` for device IPAs
4. Hit **Create Build** on the Dashboard
5. Find the IPA in your output folder / install via SideStore, AltStore, or
   Sideloadly

## How the IPA is built

After a successful `xcodebuild` run the app:

1. Locates the built `.app` in its managed DerivedData
2. Verifies the code signature (`codesign -dvv`) and logs the authority
3. Creates `Payload/App.app` and zips it into a versioned `.ipa`
4. Refreshes `latest.ipa` in the output folder

This matches the standard sideloading IPA structure. Unsigned builds still
package (SideStore/AltStore re-sign with your Apple ID), but you'll get a clear
warning that direct device installs won't work.

## Scheduled builds

**Settings → Advanced → Scheduled Builds** installs a LaunchAgent at
`~/Library/LaunchAgents/com.yambn.iOSBuildManager.scheduler.plist` that:

1. Rebuilds your project on your schedule (inside the 7-day signing window)
2. Repackages and refreshes `latest.ipa` in iCloud
3. Re-installs onto your iPhone if it's connected
4. Posts a notification either way

Pick the cadence that suits you:

- **Every N days** — a rolling interval (default 6, matches free provisioning).
- **Daily** — at a fixed time.
- **Weekly** — choose the weekdays *and* the time of day.

The app keeps running in the menu bar after you close its window, so the
schedule and quick actions stay available in the background.

### Keep apps alive with no computer (iPhone side)

For the *device* half — re-signing already-installed apps on your iPhone
automatically, without a Mac — see
**[docs/iphone-auto-refresh.md](docs/iphone-auto-refresh.md)**: a Shortcuts
automation (SideStore VPN → Refresh All → VPN off) on a weekly schedule.

## Project structure

```
iOSBuildManager/
├── iOSBuildManager/               # Xcode project root
│   ├── iOSBuildManager/           # App sources (App/Models/Services/Theme/Views)
│   ├── iOSBuildManagerTests/      # Unit tests
│   └── iOSBuildManager.xcodeproj  # GENERATED — see below
├── scripts/
│   ├── generate_pbxproj.py        # Generates the .xcodeproj + shared scheme
│   └── package-ipa.sh             # Standalone packaging helper
├── docs/                          # Screenshots
└── .github/workflows/             # CI (build + test) and release
```

⚠️ `project.pbxproj` is **generated** — never edit it by hand. See
[CONTRIBUTING.md](CONTRIBUTING.md).

## App data

Everything lives locally in `~/Library/Application Support/iOSBuildManager/`:
`settings.json`, `projects.json`, `builds.json`, per-project `DerivedData/`,
and the packaging/scheduler helper scripts.

## Contributing

PRs welcome — please read [CONTRIBUTING.md](CONTRIBUTING.md) first (the
generated-project workflow is unusual). Run the tests with:

```bash
cd iOSBuildManager && xcodebuild -scheme iOSBuildManager test
```

## License

[MIT](LICENSE)
