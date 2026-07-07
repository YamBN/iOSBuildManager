import SwiftUI

struct CertificatesView: View {
    @EnvironmentObject private var certificates: CertificateStore
    @State private var showingImportSheet = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacing) {
                header
                certificatesCard
            }
            .padding(20)
        }
        .navigationTitle("Certificates")
        .task { await certificates.refresh() }
        .sheet(isPresented: $showingImportSheet) {
            ImportCertificateSheet(store: certificates)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Signing Certificates")
                .font(.largeTitle.weight(.bold))
            Text("Code-signing identities available in your login keychain.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var certificatesCard: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionHeader(title: "Certificates", systemImage: "checkmark.seal")
                    Spacer()
                    if certificates.isRefreshing {
                        ProgressView().controlSize(.small)
                    } else {
                        Button {
                            Task { await certificates.refresh() }
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                    }
                    Button {
                        showingImportSheet = true
                    } label: {
                        Label("Import Certificate", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }

                if let err = certificates.lastError {
                    Text(err).font(.caption).foregroundStyle(.red)
                }

                if certificates.identities.isEmpty {
                    EmptyStateView(
                        title: "No Signing Certificates",
                        systemImage: "checkmark.seal",
                        description: Text("Import a .p12 or .cer file, or sign in with your Apple ID in Xcode → Settings → Accounts.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 140)
                } else {
                    VStack(spacing: 0) {
                        ForEach(certificates.identities) { identity in
                            identityRow(identity)
                            if identity.id != certificates.identities.last?.id { Divider() }
                        }
                    }
                }
            }
        }
    }

    private func identityRow(_ identity: SigningIdentity) -> some View {
        HStack(spacing: 12) {
            Image(systemName: identity.kind.systemImage)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(identity.name).font(.callout.weight(.medium)).lineLimit(1)
                if let expiration = identity.expirationDate {
                    Text("Expires \(expiration.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text(identity.hash.prefix(16) + "…")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            statusPill(identity.statusLabel)
        }
        .padding(.vertical, 8)
    }

    private func statusPill(_ label: String) -> some View {
        let color: Color = label == "Valid" ? .green : (label == "Expiring Soon" ? .orange : .red)
        return Text(label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.16), in: Capsule())
            .foregroundStyle(color)
    }
}

private struct ImportCertificateSheet: View {
    @ObservedObject var store: CertificateStore
    @Environment(\.dismiss) private var dismiss
    @State private var password: String = ""
    @State private var isImporting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Import Certificate")
                .font(.headline)
            Text("If you're importing a .p12/.pfx file, enter its password. Leave blank for .cer/.pem files.")
                .font(.caption)
                .foregroundStyle(.secondary)
            SecureField("Password (optional)", text: $password)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button {
                    isImporting = true
                    Task {
                        await store.importCertificate(password: password)
                        isImporting = false
                        dismiss()
                    }
                } label: {
                    if isImporting {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Choose File…")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isImporting)
            }
        }
        .padding(20)
        .frame(width: 360)
    }
}
