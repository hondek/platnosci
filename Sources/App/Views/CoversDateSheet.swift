import SwiftUI

struct CoversDateSheet: View {
    let title: String
    let message: String
    let confirmTitle: String
    @State private var date: Date
    let onConfirm: (Date) -> Void

    @Environment(\.dismiss) private var dismiss

    init(
        title: String,
        message: String,
        confirmTitle: String,
        date: Date,
        onConfirm: @escaping (Date) -> Void
    ) {
        self.title = title
        self.message = message
        self.confirmTitle = confirmTitle
        _date = State(initialValue: date)
        self.onConfirm = onConfirm
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker(
                        "Data",
                        selection: $date,
                        displayedComponents: .date
                    )
                } header: {
                    Text("Za kiedy")
                } footer: {
                    Text(message)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Anuluj") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(confirmTitle) {
                        onConfirm(date)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
