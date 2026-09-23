import SwiftUI

private struct PendingChore: Identifiable {
    let chore: RecurringPayment
    let slot: ChoreSlot

    var id: String { "\(chore.id.uuidString)-\(slot.key)" }
}

struct ChoresView: View {
    @Environment(PaymentStore.self) private var store

    @State private var editorTarget: PaymentEditorTarget?
    @State private var pending: PendingChore?

    var body: some View {
        NavigationStack {
            Group {
                if store.activePayments(of: .chore).isEmpty {
                    VStack(spacing: 16) {
                        if store.remindersAccessGranted == false {
                            WarningBanner(
                                icon: "checklist",
                                tint: .orange,
                                message: "Brak dostępu do Przypomnień. Wpisy nie trafią do systemowej aplikacji."
                            )
                            .padding()
                        }
                        ContentUnavailableView(
                            "Brak przypomnień",
                            systemImage: "bell",
                            description: Text("Dodaj coś poza płatnościami, na przykład wystawienie kosza.")
                        )
                    }
                } else {
                    List {
                        if store.remindersAccessGranted == false {
                            Section {
                                Text("Brak dostępu do Przypomnień. Wpisy nie trafią do systemowej aplikacji.")
                                    .font(.footnote)
                            }
                        }
                        ForEach(store.activePayments(of: .chore)) { chore in
                            Section {
                                ForEach(store.choreSlots(for: chore)) { slot in
                                    choreRow(chore, slot: slot)
                                }
                            } header: {
                                Text(chore.name)
                            } footer: {
                                HStack {
                                    Text(scheduleLine(chore))
                                    Spacer()
                                    Button("Edytuj") {
                                        editorTarget = .existing(chore)
                                    }
                                }
                                .font(.caption)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Przypomnienia")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Label("Ustawienia", systemImage: "gearshape")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editorTarget = .new
                    } label: {
                        Label("Dodaj", systemImage: "plus")
                    }
                }
            }
            .sheet(item: $editorTarget) { target in
                switch target {
                case .new:
                    PaymentEditorView(payment: nil, kind: .chore)
                case .existing(let payment):
                    PaymentEditorView(payment: payment, kind: .chore)
                }
            }
            .sheet(item: $pending) { pending in
                CoversDateSheet(
                    title: "Za kiedy?",
                    message: "Dzień, którego dotyczy to przypomnienie.",
                    confirmTitle: "Zrobione",
                    date: pending.slot.due
                ) { date in
                    store.completeOccurrence(
                        itemID: pending.chore.id,
                        key: pending.slot.key,
                        coversDate: date,
                        reopenKey: ReminderLink.chore(id: pending.chore.id, occurrence: pending.slot.key)
                    )
                }
            }
        }
    }

    private func choreRow(_ chore: RecurringPayment, slot: ChoreSlot) -> some View {
        let done = store.isChecked(itemID: chore.id, key: slot.key)
        return HStack {
            Button {
                if done {
                    store.undoOccurrence(
                        itemID: chore.id,
                        key: slot.key,
                        reopenKey: ReminderLink.chore(id: chore.id, occurrence: slot.key)
                    )
                } else {
                    pending = PendingChore(chore: chore, slot: slot)
                }
            } label: {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(done ? .green : .secondary)
                    .font(.title3)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(slot.due.formatted(date: .abbreviated, time: .omitted))
                Text(chore.effectiveTimes.map(\.formatted).joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    private func scheduleLine(_ chore: RecurringPayment) -> String {
        if chore.cadence == .weekly {
            return "Co tydzień, \(BoardNaming.weekdayName(chore.weekday ?? 2))."
        }
        return "Co miesiąc, \(chore.dueDay). dnia."
    }
}
