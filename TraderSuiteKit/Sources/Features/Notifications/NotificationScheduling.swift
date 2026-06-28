import Foundation
import UserNotifications

/// The current system notification permission, as far as the app can act on it.
public enum NotificationAuthorization: Sendable {
    /// The user has not yet been asked — requesting will show the system prompt.
    case notDetermined
    /// Notifications are allowed.
    case authorized
    /// The user has turned notifications off; only the system Settings can re-enable.
    case denied
}

/// Seam over the system notification center so the watchlist flow can be tested
/// without scheduling real notifications.
public protocol NotificationScheduling: Sendable {
    /// Ask for permission; returns whether notifications are now allowed.
    func requestAuthorization() async -> Bool
    /// Report the current permission without prompting the user.
    func authorizationStatus() async -> NotificationAuthorization
    /// Replace all previously-scheduled expiration reminders with `notifications`.
    func replaceExpirationReminders(_ notifications: [ExpirationNotification]) async
}

public extension NotificationScheduling {
    /// Default seam implementation: unknown until a concrete scheduler reports it.
    func authorizationStatus() async -> NotificationAuthorization { .notDetermined }
}

/// A scheduler that does nothing — for previews and tests.
public struct NoopNotificationScheduler: NotificationScheduling {
    public init() {}
    public func requestAuthorization() async -> Bool { false }
    public func authorizationStatus() async -> NotificationAuthorization { .notDetermined }
    public func replaceExpirationReminders(_ notifications: [ExpirationNotification]) async {}
}

/// `UNUserNotificationCenter`-backed scheduler. Identifiers we manage are
/// prefixed `expiry-`, so replacing only touches our own reminders.
public struct UserNotificationScheduler: NotificationScheduling {
    private static let idPrefix = "expiry-"

    public init() {}

    public func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    public func authorizationStatus() async -> NotificationAuthorization {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            return .notDetermined
        case .denied:
            return .denied
        case .authorized, .provisional, .ephemeral:
            return .authorized
        @unknown default:
            return .denied
        }
    }

    public func replaceExpirationReminders(_ notifications: [ExpirationNotification]) async {
        let center = UNUserNotificationCenter.current()

        // Drop our previously-scheduled reminders, leaving anything else intact.
        let pending = await center.pendingNotificationRequests()
        let staleIDs = pending.map(\.identifier).filter { $0.hasPrefix(Self.idPrefix) }
        if !staleIDs.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: staleIDs)
        }

        // Decode the fire instant in the user's local time zone so the trigger
        // fires at 15:00 local — the builder also produced it in local time.
        let calendar = Calendar.current

        for notification in notifications {
            let content = UNMutableNotificationContent()
            content.title = notification.title
            content.body = notification.body
            content.sound = .default

            var components = calendar.dateComponents(
                [.year, .month, .day, .hour, .minute], from: notification.fireDate
            )
            components.timeZone = calendar.timeZone
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(
                identifier: notification.id, content: content, trigger: trigger
            )
            try? await center.add(request)
        }
    }
}
