import Foundation
import UserNotifications

/// Thin wrapper around `UNUserNotificationCenter` for local build notifications.
/// Local only — no remote push, no tracking.
enum NotificationService {
    /// Requests permission to show notifications. Safe to call repeatedly.
    static func requestAuthorization() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Posts a local notification immediately.
    static func post(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    /// Convenience for a finished build.
    static func buildFinished(projectName: String, success: Bool, detail: String) {
        post(
            title: success ? "✅ \(projectName) built" : "❌ \(projectName) failed",
            body: detail
        )
    }
}
