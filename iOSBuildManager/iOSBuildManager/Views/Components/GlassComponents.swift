import SwiftUI

/// Pill-style status indicator with icon, label, and tinted capsule background.
struct StatusBadge: View {
    let status: BuildStatus
    var compact: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            if #available(macOS 14, *) {
                Image(systemName: status.systemImage)
                    .symbolEffect(.bounce, value: status == .building)
            } else {
                Image(systemName: status.systemImage)
            }
            if !compact {
                Text(status.displayName)
                    .font(.caption.weight(.semibold))
            }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(Theme.statusColor(status))
        .padding(.horizontal, compact ? 8 : 10)
        .padding(.vertical, 5)
        .background(Theme.statusColor(status).opacity(0.16), in: Capsule())
    }
}

/// A prominent call-to-action button that fills available width.
struct PrimaryButton: View {
    let title: String
    let systemImage: String
    var isEnabled: Bool = true
    var isLoading: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: systemImage)
                }
                Text(title)
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(!isEnabled || isLoading)
    }
}

/// A secondary, quieter button.
struct SecondaryButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
    }
}
