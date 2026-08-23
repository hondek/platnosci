import XCTest

final class PaymentsEngineTests: XCTestCase {
    private let calendar = TestSupport.calendar
    private let period = MonthKey(year: 2026, month: 8)

    func testStatusIsUpcomingBeforeDueDate() {
        let payment = TestSupport.payment(dueDay: 20)
        let now = TestSupport.date(year: 2026, month: 8, day: 5)

        let status = PaymentsEngine.status(
            for: payment,
            period: period,
            entries: [],
            now: now,
            calendar: calendar
        )

        guard case .upcoming = status else {
            return XCTFail("Oczekiwano .upcoming, otrzymano \(status)")
        }
    }

    func testStatusIsDueTodayOnDueDate() {
        let payment = TestSupport.payment(dueDay: 10, hour: 9)
        let now = TestSupport.date(year: 2026, month: 8, day: 10, hour: 7)

        let status = PaymentsEngine.status(
            for: payment,
            period: period,
            entries: [],
            now: now,
            calendar: calendar
        )

        guard case .dueToday = status else {
            return XCTFail("Oczekiwano .dueToday, otrzymano \(status)")
        }
    }

    func testStatusCountsOverdueDays() {
        let payment = TestSupport.payment(dueDay: 10)
        let now = TestSupport.date(year: 2026, month: 8, day: 17)

        let status = PaymentsEngine.status(
            for: payment,
            period: period,
            entries: [],
            now: now,
            calendar: calendar
        )

        guard case .overdue(_, let days) = status else {
            return XCTFail("Oczekiwano .overdue, otrzymano \(status)")
        }
        XCTAssertEqual(days, 7)
    }

    func testStatusIsPaidWhenEntryExists() {
        let payment = TestSupport.payment(dueDay: 10)
        let paidAt = TestSupport.date(year: 2026, month: 8, day: 9)
        let entry = TestSupport.entry(for: payment, period: period, paidAt: paidAt)
        let now = TestSupport.date(year: 2026, month: 8, day: 25)

        let status = PaymentsEngine.status(
            for: payment,
            period: period,
            entries: [entry],
            now: now,
            calendar: calendar
        )

        guard case .paid(let at, let amount) = status else {
            return XCTFail("Oczekiwano .paid, otrzymano \(status)")
        }
        XCTAssertEqual(at, paidAt)
        XCTAssertEqual(amount, payment.amount)
    }

    /// Test regresyjny: podniesienie kwoty płatności nie może zmieniać tego,
    /// ile zapłaciłeś w przeszłości. Pierwsza wersja aplikacji miała ten błąd,
    /// bo historia czytała aktualną kwotę z ustawień płatności.
    func testSummaryUsesAmountRecordedAtPaymentTime() {
        var payment = TestSupport.payment(amount: 300)
        let entry = TestSupport.entry(for: payment, period: period)

        payment.amount = Money(400)

        let summary = PaymentsEngine.summary(
            payments: [payment],
            period: period,
            entries: [entry]
        )

        XCTAssertEqual(summary.paid.value, 300)
        XCTAssertEqual(summary.total.value, 300)
    }

    func testSummaryMixesPaidAndUnpaid() {
        let first = TestSupport.payment(name: "A", amount: 300)
        let second = TestSupport.payment(name: "B", amount: 2000)
        let entry = TestSupport.entry(for: first, period: period)

        let summary = PaymentsEngine.summary(
            payments: [first, second],
            period: period,
            entries: [entry]
        )

        XCTAssertEqual(summary.totalCount, 2)
        XCTAssertEqual(summary.paidCount, 1)
        XCTAssertEqual(summary.paid.value, 300)
        XCTAssertEqual(summary.total.value, 2300)
        XCTAssertEqual(summary.remaining.value, 2000)
        XCTAssertEqual(summary.progress, 0.5)
        XCTAssertFalse(summary.isComplete)
    }

    func testSummaryIgnoresInactivePayments() {
        let active = TestSupport.payment(name: "A", amount: 300)
        let inactive = TestSupport.payment(name: "B", amount: 999, isActive: false)

        let summary = PaymentsEngine.summary(
            payments: [active, inactive],
            period: period,
            entries: []
        )

        XCTAssertEqual(summary.totalCount, 1)
        XCTAssertEqual(summary.total.value, 300)
    }

    func testSummaryOfEmptyPortfolio() {
        let summary = PaymentsEngine.summary(payments: [], period: period, entries: [])
        XCTAssertEqual(summary, .empty)
        XCTAssertEqual(summary.progress, 0)
        XCTAssertFalse(summary.isComplete)
    }

    func testUnpaidExcludesPaidAndInactive() {
        let paid = TestSupport.payment(name: "Zapłacona")
        let unpaid = TestSupport.payment(name: "Niezapłacona")
        let inactive = TestSupport.payment(name: "Wyłączona", isActive: false)
        let entry = TestSupport.entry(for: paid, period: period)

        let result = PaymentsEngine.unpaid(
            payments: [paid, unpaid, inactive],
            period: period,
            entries: [entry]
        )

        XCTAssertEqual(result.map(\.name), ["Niezapłacona"])
    }

    func testHistoryPeriodsGoBackwards() {
        let now = TestSupport.date(year: 2026, month: 2, day: 1)
        let periods = PaymentsEngine.historyPeriods(from: now, calendar: calendar, count: 3)

        XCTAssertEqual(periods, [
            MonthKey(year: 2026, month: 2),
            MonthKey(year: 2026, month: 1),
            MonthKey(year: 2025, month: 12)
        ])
    }

    func testYearlyTotalSumsOnlyThatYear() {
        let payment = TestSupport.payment(amount: 100)
        let entries = [
            TestSupport.entry(for: payment, period: MonthKey(year: 2025, month: 11)),
            TestSupport.entry(for: payment, period: MonthKey(year: 2026, month: 1)),
            TestSupport.entry(for: payment, period: MonthKey(year: 2026, month: 2))
        ]

        XCTAssertEqual(PaymentsEngine.yearlyTotal(year: 2026, entries: entries).value, 200)
        XCTAssertEqual(PaymentsEngine.yearlyTotal(year: 2025, entries: entries).value, 100)
    }
}
