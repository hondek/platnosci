import Foundation

/// Stan jednej płatności w konkretnym miesiącu.
enum PaymentStatus: Hashable, Sendable {
    case paid(at: Date, amount: Money)
    case upcoming(due: Date)
    case dueToday(due: Date)
    case overdue(due: Date, days: Int)

    var isOverdue: Bool {
        if case .overdue = self { return true }
        return false
    }
}

/// Podsumowanie miesiąca.
struct PeriodSummary: Hashable, Sendable {
    var total: Money
    var paid: Money
    var remaining: Money
    var paidCount: Int
    var totalCount: Int

    static let empty = PeriodSummary(
        total: .zero,
        paid: .zero,
        remaining: .zero,
        paidCount: 0,
        totalCount: 0
    )

    var progress: Double {
        guard totalCount > 0 else { return 0 }
        return Double(paidCount) / Double(totalCount)
    }

    var isComplete: Bool {
        totalCount > 0 && paidCount == totalCount
    }
}

/// Cała logika obliczeniowa aplikacji, bez stanu i bez zależności od UI.
enum PaymentsEngine {
    static func entry(
        paymentID: UUID,
        period: MonthKey,
        entries: [PaymentEntry]
    ) -> PaymentEntry? {
        entries.first { $0.paymentID == paymentID && $0.period == period }
    }

    static func isPaid(
        paymentID: UUID,
        period: MonthKey,
        entries: [PaymentEntry]
    ) -> Bool {
        entry(paymentID: paymentID, period: period, entries: entries) != nil
    }

    static func status(
        for payment: RecurringPayment,
        period: MonthKey,
        entries: [PaymentEntry],
        now: Date,
        calendar: Calendar
    ) -> PaymentStatus {
        if let entry = entry(paymentID: payment.id, period: period, entries: entries) {
            return .paid(at: entry.paidAt, amount: entry.amountPaid)
        }

        guard let due = period.date(
            day: payment.dueDay,
            time: payment.effectiveTimes[0],
            calendar: calendar
        ) else {
            return .upcoming(due: now)
        }

        let dueDay = calendar.startOfDay(for: due)
        let today = calendar.startOfDay(for: now)

        if dueDay == today {
            return .dueToday(due: due)
        }
        if dueDay > today {
            return .upcoming(due: due)
        }

        let days = calendar.dateComponents([.day], from: dueDay, to: today).day ?? 0
        return .overdue(due: due, days: max(days, 1))
    }

    /// Płatności, za które trzeba jeszcze zapłacić w danym miesiącu.
    static func unpaid(
        payments: [RecurringPayment],
        period: MonthKey,
        entries: [PaymentEntry]
    ) -> [RecurringPayment] {
        payments.filter { payment in
            payment.isActive && !isPaid(paymentID: payment.id, period: period, entries: entries)
        }
    }

    static func summary(
        payments: [RecurringPayment],
        period: MonthKey,
        entries: [PaymentEntry]
    ) -> PeriodSummary {
        let active = payments.filter(\.isActive)
        guard !active.isEmpty else { return .empty }

        var paidTotal = Money.zero
        var expectedTotal = Money.zero
        var paidCount = 0

        for payment in active {
            if let entry = entry(paymentID: payment.id, period: period, entries: entries) {
                paidTotal = paidTotal + entry.amountPaid
                expectedTotal = expectedTotal + entry.amountPaid
                paidCount += 1
            } else {
                expectedTotal = expectedTotal + payment.amount
            }
        }

        return PeriodSummary(
            total: expectedTotal,
            paid: paidTotal,
            remaining: expectedTotal - paidTotal,
            paidCount: paidCount,
            totalCount: active.count
        )
    }

    /// Miesiące do pokazania w historii — od najnowszego wstecz.
    static func historyPeriods(
        from now: Date,
        calendar: Calendar,
        count: Int
    ) -> [MonthKey] {
        let current = MonthKey(date: now, calendar: calendar)
        return (0..<max(count, 1)).map { current.adding(months: -$0) }
    }

    /// Ile pieniędzy przeszło przez aplikację w danym roku.
    static func yearlyTotal(
        year: Int,
        entries: [PaymentEntry],
        kind: LedgerKind? = nil
    ) -> Money {
        entries
            .filter { entry in
                entry.period.year == year && (kind == nil || entry.kind == kind)
            }
            .map(\.amountPaid)
            .total()
    }
}
