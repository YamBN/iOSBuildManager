# AI / command-line builds

The app now owns a single persistent queue for GUI, CLI, and scheduled builds.
Clients submit JSON commands through a local filesystem inbox; no HTTP server,
network service, credentials, or Computer Use is needed. Run the updated app on
one Mac under the same macOS user as the CLI. Python 3 is required (available
with Xcode's command-line tools).

## Quick start

After installing/opening the updated app, the CLI is inside its bundle:

```sh
CLI='/Applications/iOSBuildManager.app/Contents/Resources/iosbuild.py'
python3 "$CLI" projects
python3 "$CLI" enqueue \
  --project '/absolute/path/MyApp.xcodeproj' \
  --scheme MyApp \
  --configuration Release \
  --output "$HOME/Library/Mobile Documents/com~apple~CloudDocs/iOS Builds"
```

The reply is JSON: `{"id":"...","state":"submitted"}`. `submitted` means the
command is safely in the inbox, not that validation or a build has succeeded.
The CLI opens the installed app in the background. If launch fails it reports a
warning and leaves the request on disk. Use `--app '/path/to/iOSBuildManager.app'`
before the subcommand to select a development copy, or `--no-launch` if it is
already running. An older installed app cannot consume these commands.

```sh
python3 "$CLI" status REQUEST_UUID
python3 "$CLI" wait REQUEST_UUID --timeout 1800
python3 "$CLI" queue
python3 "$CLI" cancel REQUEST_UUID
```

`wait` exits 0 on success, 1 on failure/rejection/cancellation/interruption or an
unknown ID, and 2 on timeout. A timeout does not cancel the build. `cancel` only
cancels waiting jobs and returns its own command ID; inspect that command's
status to confirm acceptance. Use the existing app Cancel button for an active
build. Queue status is also visible in the Builds screen.

For a configured project, pass `--project-id UUID` instead of `--project`.
A path request registers a new project if needed. Scheme and configuration
options override that request without changing a previously saved project.
Xcode paths default to iOS; use a configured project ID for macOS/simulator
settings. Swift package paths are also accepted and build a macOS product.
`--clean` schedules cleanup immediately before that job starts.
`--install-on-device` additionally attempts installation on the first connected
device and records the separate `installResult`; it is off by default.

## Several agents / projects

Each agent uses the same CLI and receives its own ID. Generate a UUID before
submission and pass it as `--request-id UUID`. Reuse the **same ID and arguments**
when retrying a submission after losing its response; this does not run the
build twice. A changed request with the same ID is rejected by the CLI. A new
intentional build must have a new ID.

Commands are accepted in inbox creation order (filename breaks timestamp ties).
Only one worker process can hold the queue lock. Each job goes through the
existing `BuildEngine`, including packaging, history, and notifications. Failure
of one job allows the next job to run. No Git commit or push is performed.

The app snapshots project settings when it accepts the command. **It builds the
local working tree when the job starts; it does not snapshot source files or
check out a Git revision.** Keep each source checkout stable until completion,
or submit an isolated checkout. Do not edit a shared checkout during a build.

Artifacts are written beneath:

```
OUTPUT_ROOT / PROJECT_UUID / REQUEST_UUID / App-version-build.ipa
```

The successful receipt's `artifactPath` is authoritative. Each request has its
own `latest.ipa` (or Mac artifact) and cannot overwrite another request's output.
The app's Open Latest shortcut uses the selected project's build history.
Automatic artifact deletion is disabled for queued output, so old job receipts
stay usable; remove artifacts explicitly when no longer needed. History and
queue metadata do not have automatic retention in this version.

`succeeded` means the local artifact was created. If OUTPUT_ROOT is in iCloud
Drive, macOS handles upload asynchronously. This is **not** proof of completed
iCloud synchronization, signing validity on a phone, or installation. SideStore /
AltStore and the existing signing requirements still apply.

## Recovery

Queue state and commands live in:

```
~/Library/Application Support/iOSBuildManager/Queue/
```

Pending jobs survive app closure. A job that was running when its worker stopped
becomes `interrupted`, and dispatch pauses. The app cannot assume an orphaned
Xcode/signing process has stopped. Inspect and finish/stop that work first, then:

```sh
python3 "$CLI" resume --confirm-no-active-builds
```

Interrupted jobs are never replayed automatically. Resubmit explicitly with a
new ID if wanted. Corrupt queue state or a persistence failure stops dispatch
and appears in the Builds screen; the app does not discard state and pretend
success. Keep queue state when diagnosing such a failure.

Enabled schedules are migrated to CLI submission when the updated app starts.
They retain the existing cadence and best-effort connected-device installation.
Close the old app and let any old scheduled build finish before switching to the
updated version. The updated app must remain installed at the path used when
its schedule was configured; reapply schedule settings after moving it.

## Suggested instructions for coding agents

> To package this project, use the installed iOS Build Manager's bundled
> `iosbuild.py enqueue` command with this project's absolute Xcode path, scheme,
> output root and a fresh request UUID. Store the returned job ID. Check `status`
> or `wait`; only report success when `state` is `succeeded`, and return the exact
> `artifactPath`. Retry a lost submission with the same request UUID. Do not use
> Computer Use, change global app settings, modify another queued project's
> checkout, or claim iCloud synchronization/device installation from build success.

## Developer verification

```sh
python3 -m unittest discover -s scripts/tests -v
python3 scripts/generate_pbxproj.py
plutil -lint iOSBuildManager/iOSBuildManager.xcodeproj/project.pbxproj
xcodebuild -project iOSBuildManager/iOSBuildManager.xcodeproj \
  -scheme iOSBuildManager -configuration Debug \
  -derivedDataPath /absolute/path/to/external/DerivedData test
```

Tests cover concurrent CLI clients, retry deduplication/conflicts, serialized
execution, persistence failure, cancellation, corrupted commands/state, exclusive
worker ownership, and crash recovery. The end-to-end test submits via the bundled
CLI, runs an intentionally failing scheme then two real unsigned iOS fixture
builds, and verifies their separate IPA archives. It does not test iCloud sync,
live UI, signing with a personal account, or physical-device installation.
