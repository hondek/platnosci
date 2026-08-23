import XCTest

final class ReminderPlannerTests: XCTestCase {
    private let calendar = TestSupport.calendar

    private func context(
        payments: [RecurringPayment],
        entries: [PaymentEntry] = [],
        now: Date
    ) -> ReminderPlanner.Context {
        ReminderPlanner.Context(
            payments: payments,
            entries: entries,
            now: now,
            calendar: calendar,
            lookaheadMonths: 2,
            currencyCode: "PLN"
        )
    }

    /// Najważniejszy test w tym pliku. iOS trzyma maksymalnie 64 oczekujące
    /// powiadomienia i nadwyżkę wyrzuca po cichu, więc planer musi sam pilnować
    /// limitu. Sam tryb „natarczywy" chce 45 powiadomień na miesiąc.
    func testPlanNeverExceedsBudget() {
        let payments = (1...6).map {
            TestSupport.payment(name: "P\($0)", dueDay: 10, intensity: .persistent)
        }
        let now = TestSupport.date(year: 2026, month: 8, day: 1)

        let plan = ReminderPlanner.plan(context(payments: payments, now: now))

        XCTAssertLessThanOrEqual(plan.count, ReminderPlanner.budget)
        XCTAssertEqual(plan.count, ReminderPlanner.budget)
    }

    /// Budżet dzielimy przeplotem, więc pierwsza płatność nie zjada całej puli.
    func testBudgetIsSharedBetweenPayments() {
        let payments = (1...6).map {
            TestSupport.payment(name: "P\($0)", dueDay: 10, intensity: .persistent)
        }
        let now = TestSupport.date(year: 2026, month: 8, day: 1)

        let plan = ReminderPlanner.plan(context(payments: payments, now: now))
        let perPayment = Dictionary(grouping: plan, by: \.paymentID)

        XCTAssertEqual(perPayment.count, 6, "Każda płatność musi dostać przypomnienia")

        let counts = perPayment.values.map(\.count)
        let spread = (counts.max() ?? 0) - (counts.min() ?? 0)
        XCTAssertLessThanOrEqual(spread, 1, "Podział musi być równy z dokładnością do jednego")
    }

    func testPaidPeriodProducesNoReminders() {
        let payment = TestSupport.payment(dueDay: 10)
        let period = MonthKey(year: 2026, month: 8)
        let entry = TestSupport.entry(for: payment, period: period)
        let now = TestSupport.date(year: 2026, month: 8, day: 1)

        let plan = ReminderPlanner.plan(
            context(payments: [payment], entries: [entry], now: now)
        )

        XCTAssertTrue(
            plan.allSatisfy { $0.period != period },
            "Zapłacony miesiąc nie może mieć przypomnień"
        )
        XCTAssertFalse(plan.isEmpty, "Kolejne miesiące dalej muszą być zaplanowane")
    }

    func testInactivePaymentIsIgnored() {
        let payment = TestSupport.payment(isActive: false)
        let now = TestSupport.date(year: 2026, month: 8, day: 1)

        XCTAssertTrue(ReminderPlanner.plan(context(payments: [payment], now: now)).isEmpty)
    }

    func testAllRemindersAreInTheFuture() {
        let payment = TestSupport.payment(dueDay: 10)
        let now = TestSupport.date(year: 2026, month: 8, day: 15, hour: 12)

        let plan = ReminderPlanner.plan(context(payments: [payment], now: now))

        XCTAssertFalse(plan.isEmpty)
        XCTAssertTrue(plan.allSatisfy { $0.fireDate > now })
    }

    /// Płatność po terminie musi dostać serię przypomnień liczoną od dzisiaj.
    /// Gdyby okno startowało zawsze w dniu terminu, zaległa płatność nie
    /// dostałaby ani jednego powiadomienia.
    func testOverduePaymentStillGetsReminders() throws {
        let payment = TestSupport.payment(dueDay: 10, hour: 9, intensity: .persistent)
        let now = TestSupport.date(year: 2026, month: 8, day: 20, hour: 8)

        let plan = ReminderPlanner.plan(context(payments: [payment], now: now))
        let currentPeriod = MonthKey(year: 2026, month: 8)
        let currentReminders = plan.filter { $0.period == currentPeriod }

        XCTAssertFalse(currentReminders.isEmpty, "Zaległa płatność musi być przypominana")

        let earliest = try XCTUnwrap(currentReminders.map(\.fireDate).min())
        XCTAssertEqual(earliest, TestSupport.date(year: 2026, month: 8, day: 20, hour: 9))
    }

    func testOverdueReminderMentionsHowLateItIs() {
        let payment = TestSupport.payment(dueDay: 10, hour: 9)
        let now = TestSupport.date(year: 2026, month: 8, day: 20, hour: 8)

        let plan = ReminderPlanner.plan(context(payments: [payment], now: now))
        let first = plan.first { $0.period == MonthKey(year: 2026, month: 8) }

        XCTAssertTrue(first?.title.contains("zaległe") == true)
        XCTAssertTrue(first?.body.contains("10 dni po terminie") == true)
    }

    func testSingleIntensityProducesOneReminderPerPeriod() {
        let payment = TestSupport.payment(dueDay: 10, intensity: .single)
        let now = TestSupport.date(year: 2026, month: 8, day: 1)

        let plan = ReminderPlanner.plan(context(payments: [payment], now: now))
        let perPeriod = Dictionary(grouping: plan, by: \.period)

        XCTAssertEqual(perPeriod.count, 3, "Bieżący miesiąc i dwa w przód")
        XCTAssertTrue(perPeriod.values.allSatisfy { $0.count == 1 })
    }

    func testPersistentIntensityFiresThreeTimesADay() {
        let payment = TestSupport.payment(dueDay: 10, hour: 9, intensity: .persistent)
        let now = TestSupport.date(year: 2026, month: 8, day: 9)

        let plan = ReminderPlanner.plan(context(payments: [payment], now: now))
        let firstDay = plan.filter {
            calendar.isDate(
                $0.fireDate,
                inSameDayAs: TestSupport.date(year: 2026, month: 8, day: 10)
            )
        }

        XCTAssertEqual(firstDay.count, 3)
        let hours = firstDay.map { calendar.component(.hour, from: $0.fireDate) }.sorted()
        XCTAssertEqual(hours, [9, 13, 18])
    }

    func testIdentifiersAreUnique() {
        let payments = (1...3).map { TestSupport.payment(name: "P\($0)", dueDay: 10) }
        let now = TestSupport.date(year: 2026, month: 8, day: 1)

        let plan = ReminderPlanner.plan(context(payments: payments, now: now))

        XCTAssertEqual(Set(plan.map(\.identifier)).count, plan.count)
    }

    /// Identyfikator zawiera kwotę, więc zmiana kwoty tworzy nowe wpisy,
    /// a stare zostają usunięte przy synchronizacji. Bez tego w systemie
    /// zostawałaby zaplanowana treść ze starą kwotą.
    func testChangingAmountChangesIdentifiers() {
        var payment = TestSupport.payment(amount: 300, dueDay: 10)
        let now = TestSupport.date(year: 2026, month: 8, day: 1)

        let before = Set(ReminderPlanner.plan(context(payments: [payment], now: now)).map(\.identifier))

        payment.amount = Money(400)
        let after = Set(ReminderPlanner.plan(context(payments: [payment], now: now)).map(\.identifier))

        XCTAssertTrue(before.isDisjoint(with: after))
    }

    func testIdentifiersCarryPlannerPrefix() {
        let payment = TestSupport.payment()
        let now = TestSupport.date(year: 2026, month: 8, day: 1)

        let plan = ReminderPlanner.plan(context(payments: [payment], now: now))

        XCTAssertTrue(
            plan.allSatisfy { $0.identifier.hasPrefix(ReminderPlanner.identifierPrefix + ".") }
        )
    }

    func testBadgeCountsUnpaidPaymentsInThatPeriod() {
        let first = TestSupport.payment(name: "A")
        let second = TestSupport.payment(name: "B")
        let now = TestSupport.date(year: 2026, month: 8, day: 1)

        let plan = ReminderPlanner.plan(context(payments: [first, second], now: now))
        let currentPeriod = MonthKey(year: 2026, month: 8)
        let badges = Set(plan.filter { $0.period == currentPeriod }.map(\.badge))

        XCTAssertEqual(badges, [2])
    }

    func testPlanIsSortedByFireDate() {
        let payments = (1...3).map { TestSupport.payment(name: "P\($0)", dueDay: $0 * 5) }
        let now = TestSupport.date(year: 2026, month: 8, day: 1)

        let dates = ReminderPlanner.plan(context(payments: payments, now: now)).map(\.fireDate)

        XCTAssertEqual(dates, dates.sorted())
    }

    func testDayCountPhraseUsesSingularForOne() {
        XCTAssertEqual(ReminderPlanner.dayCountPhrase(1), "1 dzień")
        XCTAssertEqual(ReminderPlanner.dayCountPhrase(5), "5 dni")
    }
}
