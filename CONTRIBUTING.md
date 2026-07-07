# Contributing

Thanks for helping! A few things are unusual about this repo — read this first.

## The project file is generated

`iOSBuildManager.xcodeproj/project.pbxproj` is **generated** by
[`scripts/generate_pbxproj.py`](scripts/generate_pbxproj.py). Do not edit it by
hand, and do not rely on Xcode's "add file" flow to update it.

When you add, rename, or delete a Swift file:

1. Put the file in the right folder under `iOSBuildManager/iOSBuildManager/`.
2. Add/remove its name in the matching group inside `scripts/generate_pbxproj.py`
   (`GROUPS`, `VIEWS_SUB`, or `TEST_FILES`).
3. Regenerate and lint:

   ```bash
   python3 scripts/generate_pbxproj.py
   plutil -lint iOSBuildManager/iOSBuildManager.xcodeproj/project.pbxproj
   ```

CI fails if the committed project file doesn't match the generator's output.

## Building

```bash
cd iOSBuildManager
xcodebuild -scheme iOSBuildManager -configuration Debug build
```

Or open `iOSBuildManager/iOSBuildManager.xcodeproj` in Xcode (15+) and hit ⌘R.
No paid Apple Developer account is required — the app is ad-hoc signed.

## Testing

```bash
cd iOSBuildManager
xcodebuild -scheme iOSBuildManager test
```

Please add tests for pure parsing/logic code (`XcodeBuildService.parseSchemes`,
`DeviceStore.parseDevices`, model logic, packaging).

## Style

- Swift 6, SwiftUI, macOS 13+ APIs only (gate newer APIs with `#available`).
- Match the surrounding code's tone: small focused services, doc comments on
  types, no force-unwraps in new code.
- Keep the app local-only: no network calls, no analytics, no telemetry.

## Pull requests

- One logical change per PR.
- Describe *why*, not just *what*.
- CI must be green (project-sync check, build, tests).
