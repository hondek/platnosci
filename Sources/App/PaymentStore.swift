import Foundation
import Observation
import UserNotifications

/// Jedyne miejsce, w którym żyje stan aplikacji.
///
/// Wszystkie zmiany przechodzą przez metody tej klasy, która zapisuje dane na
/// dysk i od razu doprowadza plan powiadomień do zgodności z nowym stanem.
/// Dzięki temu nie ma sytuacji, w której dane mówią „zapłacone", a system dalej
/// trzyma zaplanowane przypomnienie.
@MainActor
@Observable
final class PaymentStore {
    private let repository: PaymentRepository
    private let notifications: NotificationService
    private let calendar: Calendar

    private(set) var snapshot: PaymentsSnapshot = .empty
    private(set) var storageError: String?
    private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    private(set) var scheduledReminderCount: Int = 0
    private(set) var nextReminderDate: Date?

    init(
        repository: PaymentRepository,
        notifications: NotificationService,
        calendar: Calendar = .current
    ) {
        self.repository = repository
        self.notifications = notifications
        self.calendar = calendar
    }

    var payments: [RecurringPayment] {
        snapshot.payments.sorted { lhs, rhs in
            if lhs.dueDay != rhs.dueDay { return lhs.dueDay < rhs.dueDay }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    var activePayments: [RecurringPayment] {
        payments.filter(\.isActive)
    }

    var entries: [PaymentEntry] {
        snapshot.entries
    }

    var currencyCode: String {
        snapshot.settings.currencyCode
    }

    var currentPeriod: MonthKey {
        MonthKey(date: Date(), calendar: calendar)
    }

    // MARK: - Cykl życia

    /// Wywoływane raz przy starcie: wczytuje dane, dosypuje przykłady przy
    /// pierwszym uruchomieniu, prosi o zgodę i uzbraja powiadomienia.
    func bootstrap() async {
        reload()

        if !snapshot.settings.didSeedExamples && snapshot.payments.isEmpty {
            snapshot.payments = PaymentsSnapshot.exampleSeed()
            snapshot.settings.didSeedExamples = true
            persist()
        }

        authorizationStatus = await notifications.requestAuthorization()
        await refreshReminders()
    }

    /// Ponowne wczytanie z dysku. Potrzebne po powrocie do aplikacji, bo dane
    /// mogła w tle zmienić akcja z powiadomienia albo odświeżanie w tle.
    func reload() {
        do {
            snapshot = try repository.load()
            storageError = nil
        } catch {
            storageError = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
            snapshot = .empty
        }
    }

    func refreshAfterReturningToForeground() async {
        reload()
        authorizationStatus = await notifications.authorizationStatus()
        await refreshReminders()
    }

    // MARK: - Odczyt

    func status(for payment: RecurringPayment, period: MonthKey) -> PaymentStatus {
        PaymentsEngine.status(
            for: payment,
            period: period,
            entries: snapshot.entries,
            now: Date(),
            calendar: calendar
        )
    }

    func summary(for period: MonthKey) -> PeriodSummary {
        PaymentsEngine.summary(
            payments: snapshot.payments,
            period: period,
            entries: snapshot.entries
        )
    }

    func unpaidCountForCurrentPeriod() -> Int {
        PaymentsEngine.unpaid(
            payments: snapshot.payments,
            period: currentPeriod,
            entries: snapshot.entries
        ).count
    }

    // MARK: - Zapis

    func addPayment(_ payment: RecurringPayment) {
        snapshot.payments.append(payment)
        persist()
        Task { await refreshReminders() }
    }

    func updatePayment(_ payment: RecurringPayment) {
        guard let index = snapshot.payments.firstIndex(where: { $0.id == payment.id }) else {
            return
        }
        snapshot.payments[index] = payment
        persist()
        Task {
            // Zmiana kwoty albo terminu unieważnia wcześniej zaplanowane treści,
            // dlatego najpierw czyścimy wszystko dla tej płatności.
            await notifications.removeReminders(forPaymentID: payment.id)
            await refreshReminders()
        }
    }

    func deletePayment(_ payment: RecurringPayment) {
        snapshot.payments.removeAll { $0.id == payment.id }
        // Wpisy historyczne zostają — mają własną kopię nazwy i kwoty, więc
        // podsumowania z poprzednich miesięcy pozostają prawdziwe.
        persist()
        Task {
            await notifications.removeReminders(forPaymentID: payment.id)
            await refreshReminders()
        }
    }

    func markPaid(_ payment: RecurringPayment, period: MonthKey, at date: Date = Date()) {
        markPaid(paymentID: payment.id, period: period, at: date)
    }

    func markPaid(paymentID: UUID, period: MonthKey, at date: Date = Date()) {
        guard let payment = snapshot.payments.first(where: { $0.id == paymentID }) else {
            return
        }

        if let index = snapshot.entries.firstIndex(where: {
            $0.paymentID == paymentID && $0.period == period
        }) {
            snapshot.entries[index].paidAt = date
        } else {
            snapshot.entries.append(
                PaymentEntry(
                    paymentID: paymentID,
                    period: period,
                    paidAt: date,
                    amountPaid: payment.amount,
                    paymentName: payment.name
                )
            )
        }

        persist()
        Task { await refreshReminders() }
    }

    func markUnpaid(_ payment: RecurringPayment, period: MonthKey) {
        snapshot.entries.removeAll { $0.paymentID == payment.id && $0.period == period }
        persist()
        Task { await refreshReminders() }
    }

    // MARK: - Powiadomienia

    func currentPlan() -> [PlannedReminder] {
        ReminderPlanner.plan(
            ReminderPlanner.Context(
                payments: snapshot.payments,
                entries: snapshot.entries,
                now: Date(),
                calendar: calendar,
                lookaheadMonths: snapshot.settings.lookaheadMonths,
                currencyCode: snapshot.settings.currencyCode
            )
        )
    }

    /// Przelicza plan, dosyła różnicę do systemu i ustawia plakietkę.
    func refreshReminders() async {
        let plan = currentPlan()
        await notifications.synchronize(plan: plan)
        await notifications.setBadge(unpaidCountForCurrentPeriod())
        scheduledReminderCount = await notifications.pendingReminderCount()
        nextReminderDate = await notifications.nextReminderDate()
    }

    func requestAuthorization() async {
        authorizationStatus = await notifications.requestAuthorization()
        await refreshReminders()
    }

    func sendTestNotification() async {
        await notifications.scheduleTestNotification()
    }

    func snooze(paymentID: UUID, period: MonthKey, title: String, body: String) async {
        await notifications.scheduleSnooze(
            paymentID: paymentID,
            period: period,
            title: title,
            body: body,
            badge: unpaidCountForCurrentPeriod()
        )
    }

    // MARK: - Prywatne

    private func persist() {
        do {
            try repository.save(snapshot)
            storageError = nil
        } catch {
            storageError = "Nie udało się zapisać danych: \(error.localizedDescription)"
        }
    }
}
