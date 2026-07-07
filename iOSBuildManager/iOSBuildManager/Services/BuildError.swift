import Foundation

enum BuildError: LocalizedError, Sendable {
    case xcodebuildMissing
    case processFailed(command: String, exitCode: Int32)
    case noSchemes
    case noAppInProducts(URL)
    case appInfoReadFailed
    case packagingFailed(String)
    case outputFolderInvalid(String)
    case scheduledBuildNotConfigured
    case generic(String)

    var errorDescription: String? {
        switch self {
        case .xcodebuildMissing:
            return "Xcode’s xcodebuild could not be found. Run Xcode at least once or run: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
        case .processFailed(let cmd, let code):
            return "‘\(cmd)’ exited with code \(code)."
        case .noSchemes:
            return "No schemes were found for this project."
        case .noAppInProducts(let url):
            return "No .app was found in build products at \(url.path)."
        case .appInfoReadFailed:
            return "Could not read the built app’s Info.plist."
        case .packagingFailed(let detail):
            return "IPA packaging failed: \(detail)"
        case .outputFolderInvalid(let detail):
            return "Output folder is not usable: \(detail)"
        case .scheduledBuildNotConfigured:
            return "No project selected for scheduled builds."
        case .generic(let detail):
            return detail
        }
    }
}
