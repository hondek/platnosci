import XCTest

final class MonthKeyTests: XCTestCase {
    private let calendar = TestSupport.calendar

    func testAddingMonthsCrossesYearForward() {
        let november = MonthKey(year: 2026, month: 11)
        XCTAssertEqual(november.adding(months: 3), MonthKey(year: 2027, month: 2))
    }

    func testAddingMonthsCrossesYearBackward() {
        let january = MonthKey(year: 2026, month: 1)
        XCTAssertEqual(january.adding(months: -1), MonthKey(year: 2025, month: 12))
        XCTAssertEqual(january.adding(months: -13), MonthKey(year: 2024, month: 12))
    }

    func testAddingZeroIsIdentity() {
        let key = MonthKey(year: 2026, month: 7)
        XCTAssertEqual(key.adding(months: 0), key)
    }

    /// Termin „31" musi wypaść ostatniego dnia lutego, a nie przelać się na marzec.
    /// Pierwsza wersja aplikacji obchodziła ten problem, zabraniając dni 29–31.
    func testDayIsClampedToShorterMonth() throws {
        let february = MonthKey(year: 2026, month: 2)
        let due = try XCTUnwrap(
            february.date(day: 31, time: TimeOfDay(hour: 9, minute: 0), calendar: calendar)
        )

        let components = calendar.dateComponents([.year, .month, .day], from: due)
        XCTAssertEqual(components.month, 2)
        XCTAssertEqual(components.day, 28)
    }

    func testDayIsClampedInLeapYear() throws {
        let february = MonthKey(year: 2028, month: 2)
        let due = try XCTUnwrap(
            february.date(day: 31, time: TimeOfDay(hour: 9, minute: 0), calendar: calendar)
        )

        XCTAssertEqual(calendar.dateComponents([.day], from: due).day, 29)
    }

    func testNumberOfDays() {
        XCTAssertEqual(MonthKey(year: 2026, month: 2).numberOfDays(calendar: calendar), 28)
        XCTAssertEqual(MonthKey(year: 2028, month: 2).numberOfDays(calendar: calendar), 29)
        XCTAssertEqual(MonthKey(year: 2026, month: 4).numberOfDays(calendar: calendar), 30)
        XCTAssertEqual(MonthKey(year: 2026, month: 12).numberOfDays(calendar: calendar), 31)
    }

    func testOrdering() {
        XCTAssertTrue(MonthKey(year: 2025, month: 12) < MonthKey(year: 2026, month: 1))
        XCTAssertTrue(MonthKey(year: 2026, month: 3) < MonthKey(year: 2026, month: 4))
    }

    func testTimeOfDayClampsOutOfRangeValues() {
        XCTAssertEqual(TimeOfDay(hour: 30, minute: 90).hour, 23)
        XCTAssertEqual(TimeOfDay(hour: 30, minute: 90).minute, 59)
        XCTAssertEqual(TimeOfDay(hour: -5, minute: -5).hour, 0)
    }
}

final class MoneyTests: XCTestCase {
    /// Powód istnienia typu `Money`: na `Double` ta suma daje 0.30000000000000004.
    func testDecimalArithmeticIsExact() {
        let sum = Money(value: Decimal(string: "0.1")!)
            + Money(value: Decimal(string: "0.2")!)
        XCTAssertEqual(sum.value, Decimal(string: "0.3"))
    }

    func testTotalOfSequence() {
        let total = [Money(300), Money(2000), Money(45)].total()
        XCTAssertEqual(total.value, 2345)
    }

    func testMinorUnits() {
        XCTAssertEqual(Money(300).minorUnits, 30000)
        XCTAssertEqual(Money(value: Decimal(string: "12.34")!).minorUnits, 1234)
    }

    /// Kwota ma trafiać do pliku jako zwykła liczba, a nie jako obiekt.
    /// Dzięki temu plik z danymi da się przeczytać i w razie potrzeby poprawić
    /// ręcznie.
    func testEncodesAsPlainNumber() throws {
        let data = try JSONEncoder().encode([Money(value: Decimal(string: "12.5")!)])
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "[12.5]")
    }

    func testRoundTrip() throws {
        let original = Money(value: Decimal(string: "1234.56")!)
        let data = try JSONEncoder().encode([original])
        let decoded = try JSONDecoder().decode([Money].self, from: data)
        XCTAssertEqual(decoded, [original])
    }
}
