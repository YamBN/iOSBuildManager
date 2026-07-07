import SwiftUI

/// macOS 13-compatible empty-state placeholder (replaces `ContentUnavailableView`,
/// which requires macOS 14+). Renders a centered icon, title, and optional
/// description with a quiet, glass-friendly style.
struct EmptyStateView: View {
    let title: String
    let systemImage: String
    var description: Text? = nil

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 36, weight: .regular))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
            if let description {
                description
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}
