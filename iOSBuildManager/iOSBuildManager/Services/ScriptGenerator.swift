import Foundation

/// Generates the Xcode Run Script Build Phase text and the helper packaging
/// script used for after-build packaging and scheduled builds.
///
/// Important: the Run Script only packages the already-built `.app` — it never
/// invokes `xcodebuild` again, which avoids build loops.
enum ScriptGenerator {
    /// Text the user pastes into Target → Build Phases → New Run Script Phase.
    static func runScriptPhase() -> String {
        """
        # iOS Build Manager – package after Xcode build (no xcodebuild inside).
        # Place in: Target → Build Phases → New Run Script Phase.
        # Only packages the already-built app for device builds; skips simulator/Mac
        # so it never re-enters the build (no build loops).

        if [ "$PLATFORM_NAME" != "iphoneos" ]; then
            exit 0
        fi

        APP_PATH="${BUILT_PRODUCTS_DIR}/${FULL_PRODUCT_NAME}"
        HELPER="$HOME/Library/Application Support/iOSBuildManager/package-ipa.sh"

        if [ ! -x "$HELPER" ]; then
            echo "warning: iOS Build Manager helper not found at \\\"$HELPER\\\" — skipping IPA packaging."
            exit 0
        fi

        "$HELPER" "$APP_PATH" "${PRODUCT_NAME}" "${MARKETING_VERSION}" "${CURRENT_PROJECT_VERSION}"
        """
    }

    /// The helper packaging script that creates Payload/, zips to .ipa, and
    /// refreshes latest.ipa in iCloud Builds.
    static let helperScriptContent: String = """
        #!/bin/bash
        # package-ipa.sh — packages a built .app into an .ipa and copies it to
        # iCloud Builds so it can be installed via SideStore / AltStore / Sideloadly.
        # Called by the Xcode Run Script phase or by iOS Build Manager.
        set -euo pipefail

        APP_PATH="${1:?usage: package-ipa.sh <app-path> [name] [version] [build]}"
        APP_NAME="${2:-$(basename "$APP_PATH" .app)}"
        VERSION="${3:-0.0.0}"
        BUILD="${4:-0}"

        OUTPUT_DIR="$HOME/Library/Mobile Documents/com~apple~CloudDocs/iOS Builds"
        mkdir -p "$OUTPUT_DIR"

        TMP="$(mktemp -d)"
        trap 'rm -rf "$TMP"' EXIT
        mkdir -p "$TMP/Payload"
        cp -R "$APP_PATH" "$TMP/Payload/${APP_NAME}.app"

        SAFE_NAME="$(echo "$APP_NAME" | tr ' ' '_')"
        IPA="$OUTPUT_DIR/${SAFE_NAME}-${VERSION}-${BUILD}.ipa"
        rm -f "$IPA"
        ( cd "$TMP" && zip -rXq "$IPA" Payload )

        # Always refresh latest.ipa for SideStore / AltStore / Sideloadly.
        cp -f "$IPA" "$OUTPUT_DIR/latest.ipa"

        echo "IPA created: $IPA"
        echo "latest.ipa updated at: $OUTPUT_DIR/latest.ipa"
        """

    /// Writes the helper script into Application Support and makes it executable.
    @discardableResult
    static func installHelperScript() throws -> URL {
        AppPaths.ensureDirectories()
        let url = AppPaths.helperScriptURL
        try helperScriptContent.write(to: url, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    /// Generates a self-contained scheduled-build script that runs `xcodebuild`
    /// headlessly and then packages the result via the helper script.
    static func generateScheduledBuildScript(for project: Project) -> String {
        // Shell-quote paths, including apostrophes and dollar signs. The CLI
        // only publishes a request; BuildEngine remains the build owner.
        func quote(_ value: String) -> String {
            "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
        }
        let cli = AppPaths.supportURL.appendingPathComponent("iosbuild.py").path
        return """
            #!/bin/sh
            set -eu
            exec /usr/bin/python3 \(quote(cli)) --app \(quote(Bundle.main.bundlePath)) enqueue --project-id \(quote(project.id.uuidString)) --install-on-device
            """
    }
}
