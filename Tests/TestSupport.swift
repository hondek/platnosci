import Foundation

/// Wspólne narzędzia testowe.
///
/// Wszystkie testy używają kalendarza w UTC, żeby wyniki nie zależały od strefy
/// czasowej maszyny budującej ani od zmiany czasu.
enum TestSupport {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }()

    static func date(
        year: Int,
        month: Int,
        day: Int,
        hour: Int = 0,
        minute: Int = 0
    ) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        guard let date = calendar.date(from: components) else {
            fatalError("Nieprawidłowa data w teście: \(year)-\(month)-\(day)")
        }
        return date
    }

    /// Stały punkt w czasie. `Date()` ma części sekundy, których zapis ISO8601
    /// nie przechowuje — użycie go w testach psułoby porównania po round-tripie.
    static let referenceDate = date(year: 2026, month: 1, day: 1, hour: 12)

    static func payment(
        name: String = "Test",
        amount: Int = 100,
        dueDay: Int = 10,
        hour: Int = 9,
        intensity: ReminderIntensity = .persistent,
        isActive: Bool = true
    ) -> RecurringPayment {
        RecurringPayment(
            name: name,
            amount: Money(amount),
            dueDay: dueDay,
            reminderTime: TimeOfDay(hour: hour, minute: 0),
            intensity: intensity,
            isActive: isActive,
            createdAt: referenceDate
        )
    }

    static func entry(
        for payment: RecurringPayment,
        period: MonthKey,
        paidAt: Date = TestSupport.referenceDate,
        amount: Money? = nil
    ) -> PaymentEntry {
        PaymentEntry(
            paymentID: payment.id,
            period: period,
            paidAt: paidAt,
            amountPaid: amount ?? payment.amount,
            paymentName: payment.name
        )
    }
}
