import Foundation
import UserNotifications

/// Dane wyciągnięte z odpowiedzi na powiadomienie.
///
/// `UNNotificationResponse` nie jest `Sendable`, więc zamiast przenosić go
/// między kontekstami współbieżności, wyłuskujemy potrzebne wartości od razu.
struct NotificationActionPayload: Sendable {
    var actionIdentifier: String
    var paymentID: UUID?
    var period: MonthKey?
    var title: String
    var body: String
}

/// Punkt składania zależności.
///
/// Potrzebny, bo akcje z powiadomień trafiają do `AppDelegate`, który nie ma
/// dostępu do stanu widoków SwiftUI. Zamiast dublować logikę, jedno miejsce
/// trzyma repozytorium, serwis powiadomień i store.
@MainActor
final class AppServices {
    static let shared = AppServices()

    let notifications: NotificationService
    let store: PaymentStore

    private init() {
        let notifications = NotificationService()
        self.notifications = notifications
        self.store = PaymentStore(
            repository: FilePaymentRepository(),
            notifications: notifications
        )
    }

    /// Obsługa przycisków z powiadomienia.
    ///
    /// Może się wykonać przy aplikacji uruchomionej w tle wyłącznie po to, żeby
    /// przyjąć tę akcję — dlatego najpierw wczytujemy dane z dysku, bo store
    /// może być jeszcze pusty.
    func handleNotificationAction(_ payload: NotificationActionPayload) async {
        store.reload()

        guard let paymentID = payload.paymentID, let period = payload.period else {
            await store.refreshReminders()
            return
        }

        switch payload.actionIdentifier {
        case NotificationService.markPaidActionIdentifier:
            store.markPaid(paymentID: paymentID, period: period)
            await store.refreshReminders()

        case NotificationService.snoozeActionIdentifier:
            await store.snooze(
                paymentID: paymentID,
                period: period,
                title: payload.title,
                body: payload.body
            )

        default:
            await store.refreshReminders()
        }
    }

    /// Wywoływane z zadania w tle: przelicza plan bez udziału użytkownika.
    func performBackgroundRefresh() async {
        store.reload()
        await store.refreshReminders()
    }
}
