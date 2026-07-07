import AppKit
import Foundation
import UniformTypeIdentifiers

/// Discovers and imports code-signing certificates from the login keychain.
@MainActor
final class CertificateStore: ObservableObject {
    @Published private(set) var identities: [SigningIdentity] = []
    @Published private(set) var isRefreshing = false
    @Published var lastError: String?

    func refresh() async {
        isRefreshing = true
        lastError = nil
        defer { isRefreshing = false }
        do {
            identities = try await Self.scan()
        } catch {
            lastError = error.localizedDescription
            identities = []
        }
    }

    /// Presents an open panel and imports a `.p12`, `.cer`, or `.pem` file into
    /// the login keychain via `security import`.
    func importCertificate(password: String) async {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = ["p12", "pfx", "cer", "pem"].compactMap { UTType(filenameExtension: $0) }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "Import"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try await Self.import_(fileURL: url, password: password)
        } catch {
            lastError = error.localizedDescription
        }
        await refresh()
    }

    // MARK: - Static helpers

    nonisolated static func scan() async throws -> [SigningIdentity] {
        let lines = try await ShellRunner.collect(
            command: "/usr/bin/security",
            arguments: ["find-identity", "-v", "-p", "codesigning"]
        )
        var identities: [SigningIdentity] = []
        let pattern = #"^\s*\d+\)\s+([0-9A-Fa-f]{40})\s+"(.+)"$"#
        let regex = try? NSRegularExpression(pattern: pattern)
        for line in lines {
            let range = NSRange(line.startIndex..., in: line)
            guard let regex, let match = regex.firstMatch(in: line, range: range),
                  let hashRange = Range(match.range(at: 1), in: line),
                  let nameRange = Range(match.range(at: 2), in: line)
            else { continue }
            let hash = String(line[hashRange])
            let name = String(line[nameRange])
            let expiration = try? await expirationDate(commonName: name)
            identities.append(SigningIdentity(hash: hash, name: name, expirationDate: expiration))
        }
        return identities
    }

    nonisolated private static func expirationDate(commonName: String) async throws -> Date? {
        let pemLines = try await ShellRunner.collect(
            command: "/usr/bin/security",
            arguments: ["find-certificate", "-c", commonName, "-p", "-a"]
        )
        let pem = pemLines.joined(separator: "\n")
        guard !pem.isEmpty else { return nil }

        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).pem")
        defer { try? FileManager.default.removeItem(at: temp) }
        try pem.write(to: temp, atomically: true, encoding: .utf8)

        let out = try await ShellRunner.collect(
            command: "/usr/bin/openssl",
            arguments: ["x509", "-in", temp.path, "-noout", "-enddate"]
        )
        guard let line = out.first(where: { $0.hasPrefix("notAfter=") }) else { return nil }
        let dateString = String(line.dropFirst("notAfter=".count))
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d HH:mm:ss yyyy zzz"
        return formatter.date(from: dateString)
    }

    nonisolated static func import_(fileURL: URL, password: String) async throws {
        let keychain = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Keychains/login.keychain-db").path
        var args = ["import", fileURL.path, "-k", keychain]
        if fileURL.pathExtension.lowercased() == "p12" || fileURL.pathExtension.lowercased() == "pfx" {
            args += ["-P", password, "-T", "/usr/bin/codesign", "-T", "/usr/bin/security"]
        } else {
            args += ["-T", "/usr/bin/codesign", "-T", "/usr/bin/security"]
        }
        for try await _ in ShellRunner.stream(command: "/usr/bin/security", arguments: args, throwOnNonZero: true) {}
    }
}
