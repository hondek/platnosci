import Foundation

/// Jedno zaplanowane powiadomienie, opisane jako czyste dane.
///
/// Planer nie zna `UserNotifications` — dzięki temu da się go przetestować bez
/// symulatora i bez uprawnień systemowych. Zamiana na `UNNotificationRequest`
/// dzieje się dopiero w warstwie aplikacji.
struct PlannedReminder: Hashable, Sendable, Identifiable {
    var identifier: String
    var paymentID: UUID
    var period: MonthKey
    var fireDate: Date
    var title: String
    var body: String
    /// Grupuje powiadomienia tej samej płatności w jeden stos na ekranie blokady.
    var threadIdentifier: String
    /// Liczba na plakietce ikony w chwili doręczenia.
    var badge: Int

    var id: String { identifier }
}

/// Buduje pełny plan przypomnień.
///
/// Kluczowe ograniczenie: iOS trzyma maksymalnie 64 oczekujące powiadomienia na
/// aplikację i po cichu wyrzuca nadwyżkę. Planer pilnuje tego limitu i dzieli
/// budżet sprawiedliwie między płatności, zamiast pozwolić jednej zająć wszystko.
enum ReminderPlanner {
    /// Prefiks identyfikatora. Po nim rozpoznajemy „nasze" powiadomienia przy
    /// sprzątaniu, żeby nie ruszać drzemek ustawionych przez użytkownika.
    static let identifierPrefix = "nag"
    /// Zostawiamy zapas do systemowego limitu 64 na drzemki i powiadomienie testowe.
    static let budget = 56

    struct Context: Sendable {
        var payments: [RecurringPayment]
        var entries: [PaymentEntry]
        var now: Date
        var calendar: Calendar
        var lookaheadMonths: Int
        var currencyCode: String

        init(
            payments: [RecurringPayment],
            entries: [PaymentEntry],
            now: Date = Date(),
            calendar: Calendar = .current,
            lookaheadMonths: Int = 2,
            currencyCode: String = "PLN"
        ) {
            self.payments = payments
            self.entries = entries
            self.now = now
            self.calendar = calendar
            self.lookaheadMonths = lookaheadMonths
            self.currencyCode = currencyCode
        }
    }

    static func plan(_ context: Context) -> [PlannedReminder] {
        let currentPeriod = MonthKey(date: context.now, calendar: context.calendar)
        let periods = (0...max(context.lookaheadMonths, 0)).map {
            currentPeriod.adding(months: $0)
        }

        // Kolejka na każdą płatność osobno, żeby móc je potem przeplatać.
        var queues: [[PlannedReminder]] = []

        for payment in context.payments where payment.isActive {
            var queue: [PlannedReminder] = []

            for period in periods {
                let alreadyPaid = PaymentsEngine.isPaid(
                    paymentID: payment.id,
                    period: period,
                    entries: context.entries
                )
                if alreadyPaid { continue }

                guard let due = period.date(
                    day: payment.dueDay,
                    time: payment.reminderTime,
                    calendar: context.calendar
                ) else { continue }

                let badge = PaymentsEngine.unpaid(
                    payments: context.payments,
                    period: period,
                    entries: context.entries
                ).count

                for fireDate in fireDates(for: payment, due: due, context: context) {
                    queue.append(
                        reminder(
                            for: payment,
                            period: period,
                            due: due,
                            fireDate: fireDate,
                            badge: badge,
                            context: context
                        )
                    )
                }
            }

            if !queue.isEmpty {
                queues.append(queue)
            }
        }

        return interleave(queues, limit: budget).sorted { $0.fireDate < $1.fireDate }
    }

    /// Momenty, w których ma zadzwonić przypomnienie dla jednego okresu.
    ///
    /// Punktem zaczepienia jest późniejsza z dwóch dat: termin płatności albo
    /// teraz. Dzięki temu płatność, której termin już minął, też dostaje serię
    /// przypomnień — zaczyna się ona od dzisiaj, a nie w przeszłości.
    private static func fireDates(
        for payment: RecurringPayment,
        due: Date,
        context: Context
    ) -> [Date] {
        let calendar = context.calendar
        let anchor = calendar.startOfDay(for: max(due, context.now))
        let intensity = payment.intensity

        var results: [Date] = []

        for dayOffset in 0..<intensity.windowDays {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: anchor),
                  let base = calendar.date(
                      bySettingHour: payment.reminderTime.hour,
                      minute: payment.reminderTime.minute,
                      second: 0,
                      of: day
                  )
            else { continue }

            for hourOffset in intensity.hourOffsets {
                guard let candidate = calendar.date(
                    byAdding: .hour,
                    value: hourOffset,
                    to: base
                ) else { continue }

                if candidate > context.now {
                    results.append(candidate)
                }
            }
        }

        return Array(results.sorted().prefix(intensity.maxOccurrences))
    }

    private static func reminder(
        for payment: RecurringPayment,
        period: MonthKey,
        due: Date,
        fireDate: Date,
        badge: Int,
        context: Context
    ) -> PlannedReminder {
        let overdueDays = context.calendar.dateComponents(
            [.day],
            from: context.calendar.startOfDay(for: due),
            to: context.calendar.startOfDay(for: fireDate)
        ).day ?? 0

        let amount = payment.amount.formatted(currencyCode: context.currencyCode)

        let title: String
        let body: String

        if overdueDays <= 0 {
            title = "\(payment.name) — \(amount)"
            body = "Dzisiaj termin płatności. Powiadomienie będzie wracać, dopóki nie oznaczysz jej jako zapłaconej."
        } else {
            title = "\(payment.name) — \(amount) (zaległe)"
            body = "\(dayCountPhrase(overdueDays)) po terminie. Powiadomienie będzie wracać, dopóki nie oznaczysz płatności jako zapłaconej."
        }

        // Identyfikator zawiera moment i kwotę, więc każda zmiana ustawień
        // tworzy nowy wpis, a stary zostaje posprzątany przy synchronizacji.
        let identifier = [
            identifierPrefix,
            payment.id.uuidString,
            period.id,
            String(Int(fireDate.timeIntervalSince1970)),
            String(payment.amount.minorUnits)
        ].joined(separator: ".")

        return PlannedReminder(
            identifier: identifier,
            paymentID: payment.id,
            period: period,
            fireDate: fireDate,
            title: title,
            body: body,
            threadIdentifier: "payment.\(payment.id.uuidString)",
            badge: badge
        )
    }

    static func dayCountPhrase(_ days: Int) -> String {
        switch days {
        case 1: return "1 dzień"
        default: return "\(days) dni"
        }
    }

    /// Przeplata kolejki po jednym elemencie, aż wyczerpie budżet.
    ///
    /// Płatność ustawiona na „natarczywie" chce 45 powiadomień na miesiąc, co
    /// samo w sobie przekracza limit systemowy. Przeplatanie gwarantuje, że przy
    /// kilku płatnościach każda dostanie swoje najbliższe terminy, zamiast
    /// pierwszej zająć całą pulę.
    private static func interleave(
        _ queues: [[PlannedReminder]],
        limit: Int
    ) -> [PlannedReminder] {
        guard limit > 0, !queues.isEmpty else { return [] }

        var result: [PlannedReminder] = []
        var index = 0
        let longest = queues.map(\.count).max() ?? 0

        while index < longest && result.count < limit {
            for queue in queues where index < queue.count {
                result.append(queue[index])
                if result.count >= limit { break }
            }
            index += 1
        }

        return result
    }
}
