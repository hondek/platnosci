import EventKit
import Foundation

struct ReminderSyncReport: Sendable {
    var externallyCompletedKeys: [String]
    var reopenedKeys: [String]
    var openCount: Int
    var nextAlarm: Date?
    var errorMessage: String?

    static let empty = ReminderSyncReport(
        externallyCompletedKeys: [],
        reopenedKeys: [],
        openCount: 0,
        nextAlarm: nil,
        errorMessage: nil
    )
}

/// Zapis planu do aplikacji Przypomnienia.
///
/// Każda lista (Płatności, Należności, grupa leków, plan lekcji) to osobny
/// kalendarz przypomnień. Wpisy rozpoznajemy po adresie `platnosci://`,
/// więc cudzych przypomnień nie ruszamy.
@MainActor
final class RemindersService {
    private let store = EKEventStore()
    private(set) var lastError: String?

    func hasFullAccess() -> Bool {
        EKEventStore.authorizationStatus(for: .reminder) == .fullAccess
    }

    func requestAccess() async -> Bool {
        if hasFullAccess() {
            lastError = nil
            return true
        }

        do {
            let granted = try await store.requestFullAccessToReminders()
            if !granted {
                lastError = "Brak dostępu do Przypomnień."
            } else {
                lastError = nil
            }
            return granted
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func synchronize(
        drafts: [SystemReminderDraft],
        doneKeys: Set<String>,
        reopenKeys: Set<String>
    ) async -> ReminderSyncReport {
        guard hasFullAccess() else {
            return ReminderSyncReport(
                externallyCompletedKeys: [],
                reopenedKeys: [],
                openCount: 0,
                nextAlarm: nil,
                errorMessage: "Brak dostępu do Przypomnień."
            )
        }

        do {
            let lists = try ensureLists(named: Set(drafts.map(\.listName)))
            let existing = await ourReminders()
            var byKey: [String: EKReminder] = [:]
            for reminder in existing {
                guard let key = ReminderLink.key(from: reminder.url) else { continue }
                if let current = byKey[key] {
                    if current.isCompleted && !reminder.isCompleted {
                        byKey[key] = reminder
                    }
                } else {
                    byKey[key] = reminder
                }
            }

            var external: [String] = []
            var reopened: [String] = []
            let openByKey = Dictionary(drafts.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })

            for (key, reminder) in byKey {
                if key.hasPrefix("test/") {
                    if let due = dueDate(of: reminder), due < Date().addingTimeInterval(-3600) {
                        try store.remove(reminder, commit: false)
                    }
                    continue
                }

                if reopenKeys.contains(key), let draft = openByKey[key], let calendar = lists[draft.listName] {
                    reminder.isCompleted = false
                    fill(reminder, with: draft, calendar: calendar)
                    try store.save(reminder, commit: false)
                    reopened.append(key)
                    continue
                }

                if let draft = openByKey[key] {
                    if reminder.isCompleted {
                        external.append(key)
                        continue
                    }
                    if let calendar = lists[draft.listName], needsUpdate(reminder, draft: draft, calendar: calendar) {
                        fill(reminder, with: draft, calendar: calendar)
                        try store.save(reminder, commit: false)
                    }
                    continue
                }

                if doneKeys.contains(key) {
                    if !reminder.isCompleted {
                        reminder.isCompleted = true
                        try store.save(reminder, commit: false)
                    }
                    continue
                }

                if !reminder.isCompleted {
                    try store.remove(reminder, commit: false)
                }
            }

            for draft in drafts where byKey[draft.key] == nil {
                guard let calendar = lists[draft.listName] else { continue }
                let reminder = EKReminder(eventStore: store)
                fill(reminder, with: draft, calendar: calendar)
                try store.save(reminder, commit: false)
            }

            try store.commit()
            lastError = nil

            let next = drafts.flatMap(\.alarms).filter { $0 > Date() }.min()
            return ReminderSyncReport(
                externallyCompletedKeys: external,
                reopenedKeys: reopened,
                openCount: drafts.count,
                nextAlarm: next,
                errorMessage: nil
            )
        } catch {
            store.reset()
            lastError = error.localizedDescription
            return ReminderSyncReport(
                externallyCompletedKeys: [],
                reopenedKeys: [],
                openCount: 0,
                nextAlarm: nil,
                errorMessage: error.localizedDescription
            )
        }
    }

    /// Jednorazowy wpis za minutę, żeby sprawdzić na telefonie, że lista działa.
    func addTestReminder() async -> String? {
        guard await requestAccess() else { return lastError }

        do {
            let lists = try ensureLists(named: [LedgerKind.outgoing.reminderListName])
            guard let calendar = lists[LedgerKind.outgoing.reminderListName] else {
                return "Nie udało się utworzyć listy Płatności."
            }
            let fire = Date().addingTimeInterval(60)
            let reminder = EKReminder(eventStore: store)
            reminder.calendar = calendar
            reminder.title = "Test przypomnienia"
            reminder.notes = "Jeśli to widzisz w aplikacji Przypomnienia, zapis działa."
            reminder.url = ReminderLink.url(for: "test/ping")
            reminder.dueDateComponents = components(from: fire)
            reminder.alarms = [EKAlarm(absoluteDate: fire)]
            try store.save(reminder, commit: true)
            lastError = nil
            return nil
        } catch {
            lastError = error.localizedDescription
            return error.localizedDescription
        }
    }

    private func ensureLists(named names: Set<String>) throws -> [String: EKCalendar] {
        guard let source = reminderSource() else {
            throw RemindersServiceError.noSource
        }

        var result: [String: EKCalendar] = [:]
        for name in names where !name.isEmpty {
            if let existing = store.calendars(for: .reminder).first(where: { $0.title == name }) {
                result[name] = existing
                continue
            }
            let calendar = EKCalendar(for: .reminder, eventStore: store)
            calendar.title = name
            calendar.source = source
            try store.saveCalendar(calendar, commit: true)
            result[name] = calendar
        }
        return result
    }

    private func reminderSource() -> EKSource? {
        if let source = store.defaultCalendarForNewReminders()?.source {
            return source
        }
        return store.sources.first { $0.sourceType == .calDAV }
            ?? store.sources.first { $0.sourceType == .local }
            ?? store.sources.first { $0.sourceType == .exchange }
    }

    private func ourReminders() async -> [EKReminder] {
        let calendars = store.calendars(for: .reminder)
        guard !calendars.isEmpty else { return [] }

        let incomplete = await reminders(matching: store.predicateForReminders(in: calendars))
        let start = Calendar.current.date(byAdding: .day, value: -120, to: Date()) ?? Date()
        let end = Calendar.current.date(byAdding: .day, value: 2, to: Date()) ?? Date()
        let completedPredicate = store.predicateForCompletedReminders(
            withCompletionDateStarting: start,
            ending: end,
            calendars: calendars
        )
        let completed = await reminders(matching: completedPredicate)
        return (incomplete + completed).filter { ReminderLink.key(from: $0.url) != nil }
    }

    private func reminders(matching predicate: NSPredicate) async -> [EKReminder] {
        await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: reminders ?? [])
            }
        }
    }

    private func fill(
        _ reminder: EKReminder,
        with draft: SystemReminderDraft,
        calendar: EKCalendar
    ) {
        reminder.calendar = calendar
        reminder.title = draft.title
        reminder.notes = draft.notes
        reminder.url = ReminderLink.url(for: draft.key)
        reminder.dueDateComponents = components(from: draft.dueDate)
        reminder.alarms = draft.alarms.map { EKAlarm(absoluteDate: $0) }
        reminder.isCompleted = false
    }

    private func needsUpdate(
        _ reminder: EKReminder,
        draft: SystemReminderDraft,
        calendar: EKCalendar
    ) -> Bool {
        if reminder.calendar?.calendarIdentifier != calendar.calendarIdentifier { return true }
        if reminder.title != draft.title { return true }
        if (reminder.notes ?? "") != draft.notes { return true }
        if !sameMinute(reminder.dueDateComponents, components(from: draft.dueDate)) { return true }
        let existing = (reminder.alarms ?? []).compactMap(\.absoluteDate).map(minuteStamp).sorted()
        let wanted = draft.alarms.map(minuteStamp).sorted()
        return existing != wanted
    }

    private func sameMinute(_ lhs: DateComponents?, _ rhs: DateComponents) -> Bool {
        guard let lhs else { return false }
        return lhs.year == rhs.year
            && lhs.month == rhs.month
            && lhs.day == rhs.day
            && lhs.hour == rhs.hour
            && lhs.minute == rhs.minute
    }

    private func minuteStamp(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return "\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)-\(parts.hour ?? 0)-\(parts.minute ?? 0)"
    }

    private func components(from date: Date) -> DateComponents {
        var parts = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: date
        )
        parts.second = 0
        return parts
    }

    private func dueDate(of reminder: EKReminder) -> Date? {
        guard let parts = reminder.dueDateComponents else { return nil }
        return Calendar.current.date(from: parts)
    }
}

private enum RemindersServiceError: LocalizedError {
    case noSource

    var errorDescription: String? {
        switch self {
        case .noSource:
            return "Na tym iPhonie nie ma miejsca, w którym da się zapisać przypomnienia."
        }
    }
}
