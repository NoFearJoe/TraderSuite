import SwiftUI
import Persistence
import ExchangeKit
#if os(iOS)
import UIKit
#endif

/// Sheet where the user configures (or disables) the expiration reminder for one
/// instrument family. Changes are committed on "Save" and immediately
/// rescheduled via `WatchlistViewModel.setNotification`.
///
/// Notification permission is requested here (lazily, on first appearance) rather
/// than at launch; if the user has denied notifications in system settings, the
/// screen explains that and offers a shortcut to Settings instead of a toggle
/// that can't take effect.
struct ExpirationNotificationSetupView: View {
    let detail: InstrumentDetail
    let model: WatchlistViewModel

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var isEnabled = false
    @State private var leadDays = 1
    @State private var isSaving = false
    @State private var authorization: NotificationAuthorization = .notDetermined

    private var watchlist: WatchlistEntity? {
        model.watchlist.first {
            $0.family == detail.family && $0.exchangeIDRaw == detail.exchange.rawValue
        }
    }

    /// Notifications are off at the system level — nothing scheduled here can fire.
    private var isDenied: Bool { authorization == .denied }

    var body: some View {
        NavigationStack {
            Form {
                if isDenied {
                    deniedSection
                }

                Section {
                    Toggle(String(localized: "notification_setup_title"), isOn: $isEnabled)
                        .disabled(isDenied)
                }

                if isEnabled && !isDenied {
                    Section {
                        Picker(String(localized: "notification_when_section"), selection: $leadDays) {
                            ForEach(Self.leadDayOptions, id: \.days) { option in
                                Text(option.label).tag(option.days)
                            }
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                    } header: {
                        Text("notification_when_section")
                    } footer: {
                        Text("notification_time_note")
                    }
                }
            }
            .navigationTitle(detail.family)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "action_cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "action_save")) {
                        Task { await save() }
                    }
                    .disabled(isSaving || isDenied)
                }
            }
        }
        .trackScreen(.notificationSetup)
        .onAppear(perform: loadCurrent)
        .task { await refreshAuthorization() }
        #if os(iOS)
        .presentationDetents([.medium])
        #endif
    }

    /// Shown when notifications are disabled for the app: explain why the reminder
    /// can't be set and link to system Settings to re-enable them.
    @ViewBuilder
    private var deniedSection: some View {
        Section {
            if let url = Self.systemSettingsURL {
                Button(String(localized: "notification_open_settings")) { openURL(url) }
            }
        } header: {
            Text("notification_denied_title")
        } footer: {
            Text("notification_denied_note")
        }
    }

    /// Deep link to the place where the user can re-enable notifications.
    private static var systemSettingsURL: URL? {
        #if os(iOS)
        return URL(string: UIApplication.openSettingsURLString)
        #elseif os(macOS)
        return URL(string: "x-apple.systempreferences:com.apple.preference.notifications")
        #else
        return nil
        #endif
    }

    // MARK: - Lead day options

    private struct LeadDayOption {
        let days: Int
        let label: String
    }

    private static let leadDayOptions: [LeadDayOption] = [
        .init(days: 0, label: L("notification_lead_0")),
        .init(days: 1, label: L("notification_lead_1")),
        .init(days: 2, label: L("notification_lead_2")),
        .init(days: 3, label: L("notification_lead_3")),
        .init(days: 4, label: L("notification_lead_4")),
        .init(days: 5, label: L("notification_lead_5")),
        .init(days: 6, label: L("notification_lead_6")),
        .init(days: 7, label: L("notification_lead_7")),
    ]

    // MARK: - Helpers

    private func loadCurrent() {
        guard let fav = watchlist else { return }
        isEnabled = fav.notificationEnabled
        leadDays = fav.notificationLeadDays
    }

    /// Resolve the current permission, prompting once if it has never been asked.
    private func refreshAuthorization() async {
        var status = await model.notificationAuthorizationStatus()
        if status == .notDetermined {
            _ = await model.requestNotificationAuthorization()
            status = await model.notificationAuthorizationStatus()
        }
        authorization = status
    }

    private func save() async {
        guard let fav = watchlist else { dismiss(); return }
        isSaving = true
        await model.setNotification(for: fav, enabled: isEnabled, leadDays: leadDays)
        env.analytics.log(.notificationConfigured, [
            .exchange: detail.exchange.rawValue,
            .enabled: isEnabled ? "true" : "false",
            .leadDays: String(leadDays),
        ])
        isSaving = false
        dismiss()
    }
}
