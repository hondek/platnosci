import SwiftUI

private struct DoseDraft: Identifiable {
    let id = UUID()
    var groupID: UUID
    var existing: MedicationDose?
    var name: String
    var time: Date
}

struct MedicationsView: View {
    @Environment(PaymentStore.self) private var store

    @State private var day = Date()
    @State private var addingGroup = false
    @State private var newGroupName = ""
    @State private var renamingGroup: MedicationGroup?
    @State private var renameText = ""
    @State private var doseDraft: DoseDraft?

    var body: some View {
        NavigationStack {
            List {
                if store.remindersAccessGranted == false {
                    Section {
                        Text("Brak dostępu do Przypomnień. Dawki nie trafią na listy w systemowej aplikacji.")
                            .font(.footnote)
                    }
                }
                Section {
                    DatePicker(
                        "Dzień",
                        selection: $day,
                        displayedComponents: .date
                    )
                } footer: {
                    Text("Każdy lek odhaczasz osobno tego dnia. Grupa, na przykład LEKARSTWA, jest listą w aplikacji Przypomnienia.")
                }

                if store.medicationGroups.isEmpty {
                    ContentUnavailableView(
                        "Brak grup",
                        systemImage: "pills",
                        description: Text("Utwórz grupę, na przykład LEKARSTWA, i dodaj dawki o konkretnych godzinach.")
                    )
                }

                ForEach(store.medicationGroups) { group in
                    Section {
                        let doses = store.doses(in: group)
                        if doses.isEmpty {
                            Text("Dodaj lek, na przykład magnez o 9:00.")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(doses) { dose in
                            doseRow(dose)
                        }
                        Button("Dodaj lek") {
                            doseDraft = DoseDraft(
                                groupID: group.id,
                                existing: nil,
                                name: "",
                                time: date(hour: 9, minute: 0)
                            )
                        }
                    } header: {
                        Text(group.name)
                    } footer: {
                        HStack {
                            Button("Zmień nazwę") {
                                renameText = group.name
                                renamingGroup = group
                            }
                            Spacer()
                            Button("Usuń grupę", role: .destructive) {
                                store.deleteMedicationGroup(group)
                            }
                        }
                        .font(.caption)
                    }
                }
            }
            .navigationTitle("Leki")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Label("Ustawienia", systemImage: "gearshape")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Nowa grupa") { addingGroup = true }
                }
            }
            .alert("Nowa grupa", isPresented: $addingGroup) {
                TextField("np. LEKARSTWA", text: $newGroupName)
                Button("Dodaj") {
                    store.addMedicationGroup(name: newGroupName)
                    newGroupName = ""
                }
                Button("Anuluj", role: .cancel) { newGroupName = "" }
            }
            .alert("Nazwa grupy", isPresented: renamePresented) {
                TextField("Nazwa", text: $renameText)
                Button("Zapisz") {
                    if let renamingGroup {
                        store.renameMedicationGroup(renamingGroup, to: renameText)
                    }
                }
                Button("Anuluj", role: .cancel) {}
            }
            .sheet(item: $doseDraft) { draft in
                DoseEditor(draft: draft) { name, time in
                    if var existing = draft.existing {
                        existing.name = name
                        existing.time = time
                        store.updateDose(existing)
                    } else {
                        store.addDose(groupID: draft.groupID, name: name, time: time)
                    }
                } onDelete: {
                    if let existing = draft.existing {
                        store.deleteDose(existing)
                    }
                }
            }
        }
    }

    private var renamePresented: Binding<Bool> {
        Binding(
            get: { renamingGroup != nil },
            set: { if !$0 { renamingGroup = nil } }
        )
    }

    private func doseRow(_ dose: MedicationDose) -> some View {
        let done = store.isDoseChecked(dose, on: day)
        return HStack {
            Button {
                store.setDose(dose, on: day, done: !done)
            } label: {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(done ? .green : .secondary)
                    .font(.title3)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(dose.name)
                Text(dose.time.formatted)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Edytuj") {
                doseDraft = DoseDraft(
                    groupID: dose.groupID,
                    existing: dose,
                    name: dose.name,
                    time: date(hour: dose.time.hour, minute: dose.time.minute)
                )
            }
            .font(.caption)
        }
    }

    private func date(hour: Int, minute: Int) -> Date {
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        return Calendar.current.date(from: components) ?? Date()
    }
}

private struct DoseEditor: View {
    let draft: DoseDraft
    let onSave: (String, TimeOfDay) -> Void
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var time: Date

    init(
        draft: DoseDraft,
        onSave: @escaping (String, TimeOfDay) -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.draft = draft
        self.onSave = onSave
        self.onDelete = onDelete
        _name = State(initialValue: draft.name)
        _time = State(initialValue: draft.time)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Nazwa, np. magnez", text: $name)
                DatePicker("Godzina", selection: $time, displayedComponents: .hourAndMinute)
                if draft.existing != nil {
                    Button("Usuń lek", role: .destructive) {
                        onDelete()
                        dismiss()
                    }
                }
            }
            .navigationTitle(draft.existing == nil ? "Nowy lek" : "Edytuj lek")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Anuluj") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Zapisz") {
                        let parts = Calendar.current.dateComponents([.hour, .minute], from: time)
                        onSave(
                            name.trimmingCharacters(in: .whitespacesAndNewlines),
                            TimeOfDay(hour: parts.hour ?? 9, minute: parts.minute ?? 0)
                        )
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
