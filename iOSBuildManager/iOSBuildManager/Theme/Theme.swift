import SwiftUI

/// Shared visual tokens for the dashboard. Uses system materials so the UI
/// adopts a glass-like, Liquid-Glass-inspired feel on macOS 13+, and the true
/// Liquid Glass effect automatically on macOS 26+ where available.
enum Theme {
    static let cornerRadius: CGFloat = 16
    static let cardCornerRadius: CGFloat = 16
    static let sidebarCornerRadius: CGFloat = 12
    static let padding: CGFloat = 18
    static let spacing: CGFloat = 16

    static let accent = Color.accentColor

    static func statusColor(_ status: BuildStatus) -> Color {
        switch status {
        case .idle: return .secondary
        case .building: return .blue
        case .success: return .green
        case .failed: return .red
        case .cancelled: return .orange
        }
    }
}

/// Deep navy backdrop used behind the whole window in dark mode, giving the
/// dashboard its "Liquid Glass" feel. Falls back to the system background in
/// light mode so the app still reads correctly there.
struct AppBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            if colorScheme == .dark {
                LinearGradient(
                    colors: [
                        Color(red: 0.043, green: 0.055, blue: 0.09),
                        Color(red: 0.02, green: 0.027, blue: 0.047)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                RadialGradient(
                    colors: [Color.accentColor.opacity(0.20), .clear],
                    center: .topLeading,
                    startRadius: 0,
                    endRadius: 900
                )
                RadialGradient(
                    colors: [Color.purple.opacity(0.08), .clear],
                    center: .bottomTrailing,
                    startRadius: 0,
                    endRadius: 700
                )
            } else {
                LinearGradient(
                    colors: [
                        Color(red: 0.955, green: 0.965, blue: 0.985),
                        Color(red: 0.92, green: 0.935, blue: 0.965)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                RadialGradient(
                    colors: [Color.accentColor.opacity(0.10), .clear],
                    center: .topLeading,
                    startRadius: 0,
                    endRadius: 900
                )
            }
        }
        .ignoresSafeArea()
    }
}

/// Glass-style container used across all dashboard cards.
struct GlassPanel<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    var cornerRadius: CGFloat = Theme.cardCornerRadius
    var padding: CGFloat = Theme.padding
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(padding)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(colorScheme == .dark ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(.regularMaterial))
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(colorScheme == .dark ? Color.white.opacity(0.03) : Color.clear)
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(colorScheme == .dark ? 0.16 : 0.18), .white.opacity(0.03)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                }
            )
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.28 : 0.10), radius: 16, x: 0, y: 8)
    }
}

/// A rounded-square icon badge with a gradient fill, used for app/product icons.
struct IconBadge: View {
    var systemImage: String
    var size: CGFloat = 44
    var colors: [Color] = [Color.accentColor, .blue]

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            Image(systemName: systemImage)
                .font(.system(size: size * 0.46, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }
}

/// A large filled circle with a centered glyph, used for prominent status
/// indicators like "Build Succeeded".
struct StatusCircle: View {
    var systemImage: String
    var color: Color
    var size: CGFloat = 52

    var body: some View {
        ZStack {
            Circle().fill(color)
            Image(systemName: systemImage)
                .font(.system(size: size * 0.5, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }
}

/// Small uppercase header used inside cards and sections.
struct SectionHeader: View {
    let title: String
    var systemImage: String?

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .foregroundStyle(.secondary)
            }
            Text(title)
                .font(.headline)
        }
    }
}

/// A large tappable tile used for the dashboard's Quick Actions grid: a
/// centered icon (optionally inside a ring) with a label underneath.
struct QuickActionTile: View {
    let title: String
    let systemImage: String
    var circled: Bool = false
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Group {
                    if circled {
                        ZStack {
                            Circle()
                                .strokeBorder(Color.primary.opacity(0.35), lineWidth: 1.5)
                                .frame(width: 44, height: 44)
                            Image(systemName: systemImage)
                                .font(.system(size: 16, weight: .semibold))
                        }
                    } else {
                        Image(systemName: systemImage)
                            .font(.system(size: 26, weight: .regular))
                    }
                }
                .frame(height: 44)
                Text(title)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(isHovering ? 0.09 : 0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}
