import XCTest

final class SystemReminderPlanTests: XCTestCase {
    private let calendar = TestSupport.calendar

    private func context(
        payments: [RecurringPayment] = [],
        entries: [PaymentEntry] = [],
        checks: [OccurrenceCheck] = [],
        groups: [MedicationGroup] = [],
        doses: [MedicationDose] = [],
        plans: [LessonPlan] = [],
        blocks: [LessonBlock] = [],
        now: Date,
        doseLookaheadDays: Int = 7,
        lessonLookaheadDays: Int = 14
    ) -> SystemReminderPlan.Context {
        SystemReminderPlan.Context(
            payments: payments,
            entries: entries,
            checks: checks,
            groups: groups,
            doses: doses,
            plans: plans,
            blocks: blocks,
            now: now,
            calendar: calendar,
            lookaheadMonths: 2,
            doseLookaheadDays: doseLookaheadDays,
            lessonLookaheadDays: lessonLookaheadDays,
            currencyCode: "PLN"
        )
    }

    func testFutureDueDayUsesEveryConfiguredHour() {
        var payment = TestSupport.payment(name: "Czynsz", amount: 300, dueDay: 10, hour: 9)
        payment.reminderTimes = [
            TimeOfDay(hour: 19, minute: 0),
            TimeOfDay(hour: 9, minute: 0)
        ]
        let now = TestSupport.date(year: 2026, month: 8, day: 1, hour: 8)

        let blueprint = SystemReminderPlan.make(context(payments: [payment], now: now))
        let august = blueprint.open.filter { $0.key.hasSuffix("2026-08") }

        XCTAssertEqual(august.count, 1)
        XCTAssertEqual(august[0].listName, "Płatności")
        XCTAssertEqual(august[0].alarms, [
            TestSupport.date(year: 2026, month: 8, day: 10, hour: 9),
            TestSupport.date(year: 2026, month: 8, day: 10, hour: 19)
        ])
        XCTAssertTrue(august[0].notes.hasPrefix("Za "))
    }

    func testPaidMonthIsNotScheduled() {
        let payment = TestSupport.payment(dueDay: 10)
        let period = MonthKey(year: 2026, month: 8)
        let entry = TestSupport.entry(for: payment, period: period)
        let now = TestSupport.date(year: 2026, month: 8, day: 1)

        let blueprint = SystemReminderPlan.make(
            context(payments: [payment], entries: [entry], now: now)
        )

        let augustKey = ReminderLink.payment(id: payment.id, period: period)
        XCTAssertFalse(blueprint.open.contains { $0.key == augustKey })
        XCTAssertTrue(blueprint.doneKeys.contains(augustKey))
        XCTAssertTrue(blueprint.open.contains { $0.key.hasSuffix("2026-09") })
    }

    func testOverduePaymentGetsTheNextFutureAlarm() {
        let payment = TestSupport.payment(dueDay: 10, hour: 9)
        let now = TestSupport.date(year: 2026, month: 8, day: 20, hour: 8)

        let blueprint = SystemReminderPlan.make(context(payments: [payment], now: now))
        let current = blueprint.open.first { $0.key.hasSuffix("2026-08") }

        XCTAssertEqual(current?.alarms, [TestSupport.date(year: 2026, month: 8, day: 20, hour: 9)])
        XCTAssertTrue(current?.title.contains("zaległe") == true)
    }

    func testIncomingPaymentUsesItsOwnList() {
        let payment = TestSupport.payment(name: "Marek", amount: 200, dueDay: 10, kind: .incoming)
        let now = TestSupport.date(year: 2026, month: 8, day: 1)

        let draft = SystemReminderPlan.make(context(payments: [payment], now: now)).open.first {
            $0.key.hasSuffix("2026-08")
        }

        XCTAssertEqual(draft?.listName, "Należności")
        XCTAssertTrue(draft?.title.contains("Do odebrania") == true)
        XCTAssertTrue(draft?.title.contains("Marek") == true)
    }

    func testChoreHasNoAmountInTheTitle() {
        let chore = TestSupport.payment(name: "Wystawienie kosza", dueDay: 4, kind: .chore)
        let now = TestSupport.date(year: 2026, month: 8, day: 1)

        let draft = SystemReminderPlan.make(context(payments: [chore], now: now)).open.first {
            $0.key.hasSuffix("2026-08")
        }

        XCTAssertEqual(draft?.listName, "Przypomnienia")
        XCTAssertEqual(draft?.title, "Wystawienie kosza")
        XCTAssertFalse(draft?.title.contains("zł") == true)
    }

    func testCheckedDoseIsSkippedAndTheGroupBecomesTheListName() {
        let group = MedicationGroup(name: "LEKARSTWA")
        let dose = MedicationDose(
            groupID: group.id,
            name: "Magnez",
            time: TimeOfDay(hour: 9, minute: 0)
        )
        let now = TestSupport.date(year: 2026, month: 8, day: 1, hour: 8)
        let today = DayKey(date: now, calendar: calendar).id
        let check = OccurrenceCheck(itemID: dose.id, occurrenceKey: today, coversDate: now)

        let blueprint = SystemReminderPlan.make(
            context(
                checks: [check],
                groups: [group],
                doses: [dose],
                now: now,
                doseLookaheadDays: 2
            )
        )

        XCTAssertTrue(blueprint.doneKeys.contains(ReminderLink.dose(id: dose.id, day: today)))
        let open = blueprint.open.filter { $0.title == "Magnez" }
        XCTAssertEqual(open.count, 1)
        XCTAssertEqual(open[0].listName, "LEKARSTWA")
        XCTAssertEqual(open[0].alarms, [TestSupport.date(year: 2026, month: 8, day: 2, hour: 9)])
    }

    func testLessonBlockBecomesAReminderAtItsStart() {
        let plan = LessonPlan(name: "Róża")
        let block = LessonBlock(
            planID: plan.id,
            weekday: 2,
            start: TimeOfDay(hour: 8, minute: 0),
            end: TimeOfDay(hour: 14, minute: 35)
        )
        let now = TestSupport.date(year: 2026, month: 8, day: 1, hour: 7)

        let blueprint = SystemReminderPlan.make(
            context(plans: [plan], blocks: [block], now: now, lessonLookaheadDays: 14)
        )
        let lessons = blueprint.open.filter { $0.listName == "Plan lekcji Róża" }

        XCTAssertFalse(lessons.isEmpty)
        XCTAssertTrue(lessons.allSatisfy { calendar.component(.weekday, from: $0.dueDate) == 2 })
        XCTAssertTrue(lessons.allSatisfy { calendar.component(.hour, from: $0.dueDate) == 8 })
        XCTAssertTrue(lessons.allSatisfy { calendar.component(.minute, from: $0.dueDate) == 0 })
        XCTAssertTrue(lessons[0].notes.contains("08:00"))
        XCTAssertTrue(lessons[0].notes.contains("14:35"))
    }

    func testReminderLinkRoundTrip() {
        let key = ReminderLink.payment(
            id: UUID(uuidString: "8E4E2C4E-0000-4000-8000-000000000001")!,
            period: MonthKey(year: 2026, month: 8)
        )
        let url = ReminderLink.url(for: key)

        XCTAssertEqual(ReminderLink.key(from: url), key)
    }

    func testLessonTitleKeepsAnExistingPrefix() {
        XCTAssertEqual(BoardNaming.lessonListTitle("Róża"), "Plan lekcji Róża")
        XCTAssertEqual(BoardNaming.lessonListTitle("Plan lekcji Kasia"), "Plan lekcji Kasia")
    }
}
