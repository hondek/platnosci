import Foundation
import UserNotifications

/// Warstwa styku z systemem powiadomień.
///
/// Plan przypomnień powstaje w `ReminderPlanner` (czysta logika), a tutaj jest
/// tylko tłumaczony na obiekty `UserNotifications` i wstawiany do systemu.
@MainActor
final class NotificationService {
    static let categoryIdentifier = "PAYMENT_REMINDER"
    static let markPaidActionIdentifier = "MARK_PAID"
    static let snoozeActionIdentifier = "SNOOZE_1H"
    static let snoozeIdentifierPrefix = "snooze"
    static let testIdentifier = "test.reminder"

    enum UserInfoKey {
        static let paymentID = "paymentID"
        static let periodYear = "periodYear"
        static let periodMonth = "periodMonth"
    }

    private let center = UNUserNotificationCenter.current()

    /// Akcje dostępne wprost z powiadomienia — bez wchodzenia do aplikacji.
    func registerCategories() {
        let markPaid = UNNotificationAction(
            identifier: Self.markPaidActionIdentifier,
            title: "Zapłacone",
            options: []
        )
        let snooze = UNNotificationAction(
            identifier: Self.snoozeActionIdentifier,
            title: "Przypomnij za godzinę",
            options: []
        )
        let category = UNNotificationCategory(
            identifier: Self.categoryIdentifier,
            actions: [markPaid, snooze],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])
    }

    func requestAuthorization() async -> UNAuthorizationStatus {
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            // Odmowa nie jest błędem programu — po prostu odczytujemy stan niżej.
        }
        return await authorizationStatus()
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    /// Doprowadza stan systemu do zgodności z planem.
    ///
    /// Zamiast kasować wszystko i wstawiać od nowa, liczymy różnicę. Powiadomienia,
    /// które już czekają z właściwą datą i kwotą, zostają nietknięte — a drzemki
    /// ustawione ręcznie przez użytkownika nie są ruszane, bo mają inny prefiks.
    func synchronize(plan: [PlannedReminder]) async {
        let pending = await center.pendingNotificationRequests()
        let plannedIdentifiers = Set(plan.map(\.identifier))
        let existingIdentifiers = Set(pending.map(\.identifier))

        let obsolete = pending
            .map(\.identifier)
            .filter { identifier in
                identifier.hasPrefix(ReminderPlanner.identifierPrefix + ".")
                    && !plannedIdentifiers.contains(identifier)
            }

        if !obsolete.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: obsolete)
        }

        for reminder in plan where !existingIdentifiers.contains(reminder.identifier) {
            try? await center.add(request(for: reminder))
        }
    }

    /// Plakietka na ikonie aplikacji.
    ///
    /// To jedyny element interfejsu iOS, który zostaje widoczny bezterminowo,
    /// dopóki liczba nie spadnie do zera. Powiadomienia da się zamknąć jednym
    /// gestem, plakietki nie.
    func setBadge(_ count: Int) async {
        try? await center.setBadgeCount(max(count, 0))
    }

    /// Kasuje stare, lokalne powiadomienia tej aplikacji. Terminy żyją teraz
    /// w aplikacji Przypomnienia, więc zostawienie obu kanałów dublowałoby alarmy.
    func retireScheduledReminders() async {
        let pending = await center.pendingNotificationRequests()
        let identifiers = pending.map(\.identifier).filter { identifier in
            identifier.hasPrefix(ReminderPlanner.identifierPrefix + ".")
                || identifier.hasPrefix(Self.snoozeIdentifierPrefix + ".")
        }
        guard !identifiers.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func pendingReminderCount() async -> Int {
        await center.pendingNotificationRequests()
            .filter { $0.identifier.hasPrefix(ReminderPlanner.identifierPrefix + ".") }
            .count
    }

    func nextReminderDate() async -> Date? {
        let pending = await center.pendingNotificationRequests()
        let dates = pending.compactMap { request -> Date? in
            guard let trigger = request.trigger as? UNCalendarNotificationTrigger else {
                return nil
            }
            return trigger.nextTriggerDate()
        }
        return dates.min()
    }

    func removeReminders(forPaymentID paymentID: UUID) async {
        let pending = await center.pendingNotificationRequests()
        let identifiers = pending
            .map(\.identifier)
            .filter { $0.contains(paymentID.uuidString) }
        guard !identifiers.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    /// Odłożenie przypomnienia o godzinę. Ma osobny prefiks, żeby synchronizacja
    /// planu go nie sprzątnęła.
    func scheduleSnooze(
        paymentID: UUID,
        period: MonthKey,
        title: String,
        body: String,
        badge: Int
    ) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.badge = NSNumber(value: max(badge, 0))
        content.categoryIdentifier = Self.categoryIdentifier
        content.threadIdentifier = "payment.\(paymentID.uuidString)"
        content.interruptionLevel = .timeSensitive
        content.userInfo = [
            UserInfoKey.paymentID: paymentID.uuidString,
            UserInfoKey.periodYear: period.year,
            UserInfoKey.periodMonth: period.month
        ]

        let identifier = [
            Self.snoozeIdentifierPrefix,
            paymentID.uuidString,
            period.id,
            String(Int(Date().timeIntervalSince1970))
        ].joined(separator: ".")

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 3600, repeats: false)
        )

        try? await center.add(request)
    }

    /// Powiadomienie kontrolne za 15 sekund — służy do sprawdzenia na telefonie,
    /// czy zgody i akcje działają, bez czekania na prawdziwy termin.
    func scheduleTestNotification() async {
        let content = UNMutableNotificationContent()
        content.title = "Test powiadomienia"
        content.body = "Jeśli to widzisz, przypomnienia działają poprawnie."
        content.sound = .default
        content.interruptionLevel = .timeSensitive

        let request = UNNotificationRequest(
            identifier: Self.testIdentifier,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 15, repeats: false)
        )

        try? await center.add(request)
    }

    private func request(for reminder: PlannedReminder) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.body = reminder.body
        content.sound = .default
        content.badge = NSNumber(value: max(reminder.badge, 0))
        content.categoryIdentifier = Self.categoryIdentifier
        content.threadIdentifier = reminder.threadIdentifier
        // `.timeSensitive` przebija tryb skupienia i „nie przeszkadzać".
        // Pełny efekt wymaga uprawnienia Time Sensitive Notifications z płatnego
        // konta Apple; bez niego system po prostu traktuje je jak zwykłe.
        content.interruptionLevel = .timeSensitive
        content.userInfo = [
            UserInfoKey.paymentID: reminder.paymentID.uuidString,
            UserInfoKey.periodYear: reminder.period.year,
            UserInfoKey.periodMonth: reminder.period.month
        ]

        var components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: reminder.fireDate
        )
        components.second = 0

        return UNNotificationRequest(
            identifier: reminder.identifier,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        )
    }
}
