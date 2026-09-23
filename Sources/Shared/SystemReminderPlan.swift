import Foundation

/// Jedno przypomnienie do zapisania w aplikacji Przypomnienia.
struct SystemReminderDraft: Hashable, Sendable, Identifiable {
    var key: String
    var listName: String
    var title: String
    var notes: String
    var dueDate: Date
    var alarms: [Date]

    var id: String { key }
}

/// Otwarte wpisy oraz klucze już odhaczone w tym samym oknie.
struct SystemReminderBlueprint: Hashable, Sendable {
    var open: [SystemReminderDraft]
    var doneKeys: Set<String>
}

/// Jedno wystąpienie przypomnienia niepłatnościowego.
struct ChoreSlot: Hashable, Sendable, Identifiable {
    var key: String
    var due: Date

    var id: String { key }
}

/// Adres wpisu w Przypomnieniach. Po nim rozpoznajemy nasze rekordy przy synchronizacji.
enum ReminderLink {
    static let scheme = "hondek"

    static func payment(id: UUID, period: MonthKey) -> String {
        "pay/\(id.uuidString)/\(period.id)"
    }

    static func chore(id: UUID, occurrence: String) -> String {
        "chore/\(id.uuidString)/\(occurrence)"
    }

    static func dose(id: UUID, day: String) -> String {
        "dose/\(id.uuidString)/\(day)"
    }

    static func lesson(id: UUID, day: String) -> String {
        "lesson/\(id.uuidString)/\(day)"
    }

    static func url(for key: String) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "reminder"
        components.path = "/" + key
        return components.url
    }

    static func key(from url: URL?) -> String? {
        guard let url, url.scheme == scheme else { return nil }
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard path.contains("/") else { return nil }
        return path
    }
}

/// Buduje listę wpisów dla aplikacji Przypomnienia.
///
/// Jeden nieodhaczony termin to jeden wpis. Godziny ustawione przez użytkownika
/// stają się alarmami tego wpisu. Wpis zostaje na liście, dopóki ktoś go nie odhaczy,
/// więc nie trzeba dublować go kilkanaście razy jak przy lokalnych powiadomieniach.
enum SystemReminderPlan {
    struct Context: Sendable {
        var payments: [RecurringPayment]
        var entries: [PaymentEntry]
        var checks: [OccurrenceCheck]
        var groups: [MedicationGroup]
        var doses: [MedicationDose]
        var plans: [LessonPlan]
        var blocks: [LessonBlock]
        var now: Date
        var calendar: Calendar
        var lookaheadMonths: Int
        var doseLookaheadDays: Int
        var lessonLookaheadDays: Int
        var currencyCode: String

        init(
            payments: [RecurringPayment],
            entries: [PaymentEntry] = [],
            checks: [OccurrenceCheck] = [],
            groups: [MedicationGroup] = [],
            doses: [MedicationDose] = [],
            plans: [LessonPlan] = [],
            blocks: [LessonBlock] = [],
            now: Date = Date(),
            calendar: Calendar = .current,
            lookaheadMonths: Int = 2,
            doseLookaheadDays: Int = 7,
            lessonLookaheadDays: Int = 14,
            currencyCode: String = "PLN"
        ) {
            self.payments = payments
            self.entries = entries
            self.checks = checks
            self.groups = groups
            self.doses = doses
            self.plans = plans
            self.blocks = blocks
            self.now = now
            self.calendar = calendar
            self.lookaheadMonths = lookaheadMonths
            self.doseLookaheadDays = doseLookaheadDays
            self.lessonLookaheadDays = lessonLookaheadDays
            self.currencyCode = currencyCode
        }
    }

    static func make(_ context: Context) -> SystemReminderBlueprint {
        var open: [SystemReminderDraft] = []
        var done: Set<String> = []

        let currentPeriod = MonthKey(date: context.now, calendar: context.calendar)
        let periods = (0...max(context.lookaheadMonths, 0)).map {
            currentPeriod.adding(months: $0)
        }

        for payment in context.payments where payment.isActive && payment.kind != .chore {
            for period in periods {
                let key = ReminderLink.payment(id: payment.id, period: period)
                guard let due = period.date(
                    day: payment.dueDay,
                    time: payment.effectiveTimes[0],
                    calendar: context.calendar
                ) else { continue }

                if PaymentsEngine.isPaid(
                    paymentID: payment.id,
                    period: period,
                    entries: context.entries
                ) {
                    done.insert(key)
                    continue
                }

                open.append(draft(for: payment, key: key, due: due, context: context))
            }
        }

        for chore in context.payments where chore.isActive && chore.kind == .chore {
            for slot in choreSlots(
                for: chore,
                now: context.now,
                calendar: context.calendar,
                lookaheadMonths: context.lookaheadMonths
            ) {
                let key = ReminderLink.chore(id: chore.id, occurrence: slot.key)
                if isChecked(itemID: chore.id, key: slot.key, checks: context.checks) {
                    done.insert(key)
                } else {
                    open.append(draft(for: chore, key: key, due: slot.due, context: context))
                }
            }
        }

        let groupsByID = Dictionary(uniqueKeysWithValues: context.groups.map { ($0.id, $0) })
        let today = context.calendar.startOfDay(for: context.now)

        for dose in context.doses where dose.isActive {
            guard let group = groupsByID[dose.groupID] else { continue }
            for offset in 0..<max(context.doseLookaheadDays, 1) {
                guard let dayDate = context.calendar.date(byAdding: .day, value: offset, to: today),
                      let due = DayKey(date: dayDate, calendar: context.calendar)
                        .date(time: dose.time, calendar: context.calendar)
                else { continue }

                let dayID = DayKey(date: dayDate, calendar: context.calendar).id
                let key = ReminderLink.dose(id: dose.id, day: dayID)
                if isChecked(itemID: dose.id, key: dayID, checks: context.checks) {
                    done.insert(key)
                    continue
                }

                let alarms = due > context.now ? [due] : []
                open.append(
                    SystemReminderDraft(
                        key: key,
                        listName: group.listName,
                        title: dose.name,
                        notes: "Dawka o \(dose.time.formatted).",
                        dueDate: due,
                        alarms: alarms
                    )
                )
            }
        }

        let plansByID = Dictionary(uniqueKeysWithValues: context.plans.map { ($0.id, $0) })
        for block in context.blocks {
            guard let plan = plansByID[block.planID] else { continue }
            for offset in 0..<max(context.lessonLookaheadDays, 1) {
                guard let dayDate = context.calendar.date(byAdding: .day, value: offset, to: today),
                      context.calendar.component(.weekday, from: dayDate) == block.weekday,
                      let start = DayKey(date: dayDate, calendar: context.calendar)
                        .date(time: block.start, calendar: context.calendar),
                      start > context.now
                else { continue }

                let dayID = DayKey(date: dayDate, calendar: context.calendar).id
                var notes = "\(block.start.formatted)–\(block.end.formatted)"
                if !block.note.isEmpty {
                    notes += " · \(block.note)"
                }

                open.append(
                    SystemReminderDraft(
                        key: ReminderLink.lesson(id: block.id, day: dayID),
                        listName: plan.listTitle,
                        title: plan.listTitle,
                        notes: notes,
                        dueDate: start,
                        alarms: [start]
                    )
                )
            }
        }

        open.sort { $0.dueDate < $1.dueDate }
        return SystemReminderBlueprint(open: open, doneKeys: done)
    }

    static func choreSlots(
        for chore: RecurringPayment,
        now: Date,
        calendar: Calendar,
        lookaheadMonths: Int
    ) -> [ChoreSlot] {
        if chore.cadence == .weekly {
            return weeklySlots(for: chore, now: now, calendar: calendar, lookaheadMonths: lookaheadMonths)
        }

        let current = MonthKey(date: now, calendar: calendar)
        return (0...max(lookaheadMonths, 0)).compactMap { offset in
            let period = current.adding(months: offset)
            guard let due = period.date(
                day: chore.dueDay,
                time: chore.effectiveTimes[0],
                calendar: calendar
            ) else { return nil }
            return ChoreSlot(key: period.id, due: due)
        }
    }

    /// Alarmy jednego wpisu.
    ///
    /// Termin w przyszłości dostaje wszystkie ustawione godziny tego dnia.
    /// Termin miniony albo dzisiejszy z godzinami już za nami dostaje najbliższe
    /// przyszłe godziny — wpis i tak zostaje na liście jako zaległy.
    static func alarmDates(
        due: Date,
        times: [TimeOfDay],
        now: Date,
        calendar: Calendar
    ) -> [Date] {
        let times = times.isEmpty ? [TimeOfDay.morning] : times.sorted()
        let dueDay = calendar.startOfDay(for: due)
        let today = calendar.startOfDay(for: now)

        if dueDay > today {
            return times.compactMap { date(dueDay, time: $0, calendar: calendar) }
        }

        let laterToday = times
            .compactMap { date(today, time: $0, calendar: calendar) }
            .filter { $0 > now }
        if !laterToday.isEmpty {
            return laterToday
        }

        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) else {
            return []
        }
        return times.compactMap { date(tomorrow, time: $0, calendar: calendar) }
    }

    private static func weeklySlots(
        for chore: RecurringPayment,
        now: Date,
        calendar: Calendar,
        lookaheadMonths: Int
    ) -> [ChoreSlot] {
        let weekday = chore.weekday ?? 2
        let weeks = max(lookaheadMonths, 1) * 4
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: now) else { return [] }

        var slots: [ChoreSlot] = []
        for week in 0..<weeks {
            guard let weekStart = calendar.date(byAdding: .day, value: week * 7, to: interval.start) else {
                continue
            }
            for offset in 0..<7 {
                guard let day = calendar.date(byAdding: .day, value: offset, to: weekStart),
                      calendar.component(.weekday, from: day) == weekday
                else { continue }
                let dayKey = DayKey(date: day, calendar: calendar)
                guard let due = dayKey.date(time: chore.effectiveTimes[0], calendar: calendar) else {
                    continue
                }
                slots.append(ChoreSlot(key: dayKey.id, due: due))
            }
        }
        return slots
    }

    private static func draft(
        for payment: RecurringPayment,
        key: String,
        due: Date,
        context: Context
    ) -> SystemReminderDraft {
        let overdueDays = context.calendar.dateComponents(
            [.day],
            from: context.calendar.startOfDay(for: due),
            to: context.calendar.startOfDay(for: context.now)
        ).day ?? 0

        let dueText = due.formatted(date: .abbreviated, time: .omitted)
        var notes = "Za \(dueText)."
        if !payment.note.isEmpty {
            notes += " \(payment.note)"
        }
        if overdueDays > 0 {
            notes += " \(ReminderPlanner.dayCountPhrase(overdueDays)) po terminie."
        }

        let title: String
        switch payment.kind {
        case .outgoing:
            let amount = payment.amount.formatted(currencyCode: context.currencyCode)
            title = overdueDays > 0
                ? "\(payment.name) — \(amount) (zaległe)"
                : "\(payment.name) — \(amount)"
        case .incoming:
            let amount = payment.amount.formatted(currencyCode: context.currencyCode)
            title = overdueDays > 0
                ? "Do odebrania: \(payment.name) — \(amount) (zaległe)"
                : "Do odebrania: \(payment.name) — \(amount)"
        case .chore:
            title = overdueDays > 0 ? "\(payment.name) (zaległe)" : payment.name
        }

        return SystemReminderDraft(
            key: key,
            listName: payment.kind.reminderListName,
            title: title,
            notes: notes,
            dueDate: due,
            alarms: alarmDates(
                due: due,
                times: payment.effectiveTimes,
                now: context.now,
                calendar: context.calendar
            )
        )
    }

    private static func isChecked(
        itemID: UUID,
        key: String,
        checks: [OccurrenceCheck]
    ) -> Bool {
        checks.contains { $0.itemID == itemID && $0.occurrenceKey == key }
    }

    private static func date(_ day: Date, time: TimeOfDay, calendar: Calendar) -> Date? {
        var components = calendar.dateComponents([.year, .month, .day], from: day)
        components.hour = time.hour
        components.minute = time.minute
        components.second = 0
        return calendar.date(from: components)
    }
}
