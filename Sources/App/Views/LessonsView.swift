import SwiftUI

private struct BlockDraft: Identifiable {
    let id: UUID
    var planID: UUID
    var weekday: Int
    var start: Date
    var end: Date
    var note: String
    var isNew: Bool

    init(block: LessonBlock) {
        id = block.id
        planID = block.planID
        weekday = block.weekday
        start = BlockDraft.date(block.start)
        end = BlockDraft.date(block.end)
        note = block.note
        isNew = false
    }

    init(planID: UUID) {
        id = UUID()
        self.planID = planID
        weekday = 2
        start = BlockDraft.date(TimeOfDay(hour: 8, minute: 0))
        end = BlockDraft.date(TimeOfDay(hour: 14, minute: 35))
        note = ""
        isNew = true
    }

    private static func date(_ time: TimeOfDay) -> Date {
        var components = DateComponents()
        components.hour = time.hour
        components.minute = time.minute
        return Calendar.current.date(from: components) ?? Date()
    }
}

struct LessonsView: View {
    @Environment(PaymentStore.self) private var store

    @State private var addingPlan = false
    @State private var newPlanName = ""
    @State private var renamingPlan: LessonPlan?
    @State private var renameText = ""
    @State private var blockDraft: BlockDraft?

    private let calendar = Calendar.current

    var body: some View {
        NavigationStack {
            List {
                if store.remindersAccessGranted == false {
                    Section {
                        Text("Brak dostępu do Przypomnień. Bloki nie dostaną alarmu o godzinie rozpoczęcia.")
                            .font(.footnote)
                    }
                }
                if store.lessonPlans.isEmpty {
                    ContentUnavailableView(
                        "Brak planów",
                        systemImage: "calendar",
                        description: Text("Dodaj plan, na przykład Róża albo Kasia. W Przypomnieniach dostanie listę „Plan lekcji Róża”.")
                    )
                }

                ForEach(store.lessonPlans) { plan in
                    Section {
                        let blocks = store.blocks(in: plan)
                        if blocks.isEmpty {
                            Text("Dodaj pierwszy blok, na przykład poniedziałek 8:00–14:35.")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(BoardNaming.orderedWeekdays(calendar: calendar), id: \.self) { weekday in
                            let dayBlocks = blocks.filter { $0.weekday == weekday }
                            if !dayBlocks.isEmpty {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(BoardNaming.weekdayName(weekday, calendar: calendar))
                                        .font(.headline)
                                        .foregroundStyle(isToday(weekday) ? Color.accentColor : .primary)
                                    ForEach(dayBlocks) { block in
                                        Button {
                                            blockDraft = BlockDraft(block: block)
                                        } label: {
                                            HStack {
                                                Text("\(block.start.formatted)–\(block.end.formatted)")
                                                if !block.note.isEmpty {
                                                    Text(block.note)
                                                        .foregroundStyle(.secondary)
                                                }
                                                Spacer()
                                            }
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                        Button("Dodaj godziny") {
                            blockDraft = BlockDraft(planID: plan.id)
                        }
                    } header: {
                        Text(plan.listTitle)
                    } footer: {
                        HStack {
                            Button("Zmień nazwę") {
                                renameText = plan.name
                                renamingPlan = plan
                            }
                            Spacer()
                            Button("Usuń plan", role: .destructive) {
                                store.deleteLessonPlan(plan)
                            }
                        }
                        .font(.caption)
                    }
                }
            }
            .navigationTitle("Plan lekcji")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Label("Ustawienia", systemImage: "gearshape")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Nowy plan") { addingPlan = true }
                }
            }
            .alert("Nowy plan", isPresented: $addingPlan) {
                TextField("np. Róża", text: $newPlanName)
                Button("Dodaj") {
                    store.addLessonPlan(name: newPlanName)
                    newPlanName = ""
                }
                Button("Anuluj", role: .cancel) { newPlanName = "" }
            } message: {
                Text("Na liście pojawi się jako „Plan lekcji” i wpisane imię.")
            }
            .alert("Nazwa planu", isPresented: renamePresented) {
                TextField("Imię", text: $renameText)
                Button("Zapisz") {
                    if let renamingPlan {
                        store.renameLessonPlan(renamingPlan, to: renameText)
                    }
                }
                Button("Anuluj", role: .cancel) {}
            }
            .sheet(item: $blockDraft) { draft in
                BlockEditor(draft: draft) { block in
                    store.saveLessonBlock(block)
                } onDelete: {
                    if !draft.isNew {
                        store.deleteLessonBlock(
                            LessonBlock(
                                id: draft.id,
                                planID: draft.planID,
                                weekday: draft.weekday,
                                start: .morning,
                                end: TimeOfDay(hour: 10, minute: 0)
                            )
                        )
                    }
                }
            }
        }
    }

    private var renamePresented: Binding<Bool> {
        Binding(
            get: { renamingPlan != nil },
            set: { if !$0 { renamingPlan = nil } }
        )
    }

    private func isToday(_ weekday: Int) -> Bool {
        calendar.component(.weekday, from: Date()) == weekday
    }
}

private struct BlockEditor: View {
    let draft: BlockDraft
    let onSave: (LessonBlock) -> Void
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var weekday: Int
    @State private var start: Date
    @State private var end: Date
    @State private var note: String

    init(
        draft: BlockDraft,
        onSave: @escaping (LessonBlock) -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.draft = draft
        self.onSave = onSave
        self.onDelete = onDelete
        _weekday = State(initialValue: draft.weekday)
        _start = State(initialValue: draft.start)
        _end = State(initialValue: draft.end)
        _note = State(initialValue: draft.note)
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Dzień", selection: $weekday) {
                    ForEach(BoardNaming.orderedWeekdays(), id: \.self) { day in
                        Text(BoardNaming.weekdayName(day)).tag(day)
                    }
                }
                DatePicker("Od", selection: $start, displayedComponents: .hourAndMinute)
                DatePicker("Do", selection: $end, displayedComponents: .hourAndMinute)
                TextField("Opcjonalnie, np. matematyka", text: $note)

                if !draft.isNew {
                    Button("Usuń blok", role: .destructive) {
                        onDelete()
                        dismiss()
                    }
                }
            }
            .navigationTitle(draft.isNew ? "Nowy blok" : "Edytuj blok")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Anuluj") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Zapisz") {
                        onSave(
                            LessonBlock(
                                id: draft.id,
                                planID: draft.planID,
                                weekday: weekday,
                                start: time(from: start),
                                end: time(from: end),
                                note: note.trimmingCharacters(in: .whitespacesAndNewlines)
                            )
                        )
                        dismiss()
                    }
                    .disabled(!rangeIsValid)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var rangeIsValid: Bool {
        let from = time(from: start)
        let to = time(from: end)
        return (from.hour, from.minute) < (to.hour, to.minute)
    }

    private func time(from date: Date) -> TimeOfDay {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return TimeOfDay(hour: parts.hour ?? 8, minute: parts.minute ?? 0)
    }
}
