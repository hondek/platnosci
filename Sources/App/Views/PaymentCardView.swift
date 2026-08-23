import SwiftUI

struct PaymentCardView: View {
    let payment: RecurringPayment
    let status: PaymentStatus
    let currencyCode: String
    let onMarkPaid: () -> Void
    let onMarkUnpaid: () -> Void
    let onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if !payment.note.isEmpty {
                Text(payment.note)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Divider()

            statusSection
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            // Zaległe płatności dostają obwódkę, żeby były widoczne
            // jednym spojrzeniem na listę.
            if status.isOverdue {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(.red.opacity(0.5), lineWidth: 2)
            }
        }
        .contextMenu {
            Button("Edytuj", systemImage: "pencil", action: onEdit)
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(payment.name)
                    .font(.title3.bold())
                Text(payment.amount.formatted(currencyCode: currencyCode))
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: iconName)
                .font(.system(size: 32))
                .foregroundStyle(tint)
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        switch status {
        case .paid(let date, let amount):
            VStack(alignment: .leading, spacing: 10) {
                Label(
                    "Zapłacone \(amount.formatted(currencyCode: currencyCode))",
                    systemImage: "checkmark.circle.fill"
                )
                .font(.headline)
                .foregroundStyle(.green)

                Text(date.formatted(date: .abbreviated, time: .shortened))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Button("Cofnij oznaczenie", systemImage: "arrow.uturn.backward", action: onMarkUnpaid)
                    .font(.subheadline)
            }

        case .upcoming(let due):
            unpaidSection(
                headline: "Termin \(due.formatted(date: .abbreviated, time: .omitted))",
                detail: "Przypomnienie o \(payment.reminderTime.formatted), tryb: \(payment.intensity.title.lowercased()).",
                tint: .secondary
            )

        case .dueToday(let due):
            unpaidSection(
                headline: "Termin dzisiaj",
                detail: "Przypomnienie o \(due.formatted(date: .omitted, time: .shortened)) i dalej, dopóki nie oznaczysz.",
                tint: .orange
            )

        case .overdue(_, let days):
            unpaidSection(
                headline: "Zaległe — \(ReminderPlanner.dayCountPhrase(days)) po terminie",
                detail: "Przypomnienia wracają, dopóki nie oznaczysz płatności.",
                tint: .red
            )
        }
    }

    private func unpaidSection(
        headline: String,
        detail: String,
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(headline)
                .font(.headline)
                .foregroundStyle(tint)

            Text(detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: onMarkPaid) {
                Label("Oznacz jako zapłacone", systemImage: "checkmark")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    private var iconName: String {
        switch status {
        case .paid: return "checkmark.circle.fill"
        case .upcoming: return "clock"
        case .dueToday: return "exclamationmark.circle.fill"
        case .overdue: return "exclamationmark.triangle.fill"
        }
    }

    private var tint: Color {
        switch status {
        case .paid: return .green
        case .upcoming: return .secondary
        case .dueToday: return .orange
        case .overdue: return .red
        }
    }
}
