import SwiftUI

struct PaymentCardView: View {
    let payment: RecurringPayment
    let status: PaymentStatus
    let coversDate: Date?
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
                if payment.kind.handlesMoney {
                    Text(payment.amount.formatted(currencyCode: currencyCode))
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                Text(hoursLine)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: iconName)
                .font(.system(size: 32))
                .foregroundStyle(tint)
        }
    }

    private var hoursLine: String {
        let hours = payment.effectiveTimes.map(\.formatted).joined(separator: ", ")
        return "Przypomnienia o \(hours)"
    }

    @ViewBuilder
    private var statusSection: some View {
        switch status {
        case .paid(let date, let amount):
            VStack(alignment: .leading, spacing: 10) {
                Label(doneHeadline(amount: amount), systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.green)

                if let coversDate {
                    Text("Za \(coversDate.formatted(date: .abbreviated, time: .omitted))")
                        .font(.subheadline)
                }

                Text("Oznaczone \(date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Button("Cofnij oznaczenie", systemImage: "arrow.uturn.backward", action: onMarkUnpaid)
                    .font(.subheadline)
            }

        case .upcoming(let due):
            unpaidSection(
                headline: "Termin \(due.formatted(date: .abbreviated, time: .omitted))",
                detail: listDetail,
                tint: .secondary
            )

        case .dueToday:
            unpaidSection(
                headline: "Termin dzisiaj",
                detail: listDetail,
                tint: .orange
            )

        case .overdue(_, let days):
            unpaidSection(
                headline: "Zaległe — \(ReminderPlanner.dayCountPhrase(days)) po terminie",
                detail: "Wpis zostaje na liście „\(payment.kind.reminderListName)”, dopóki go nie odhaczysz.",
                tint: .red
            )
        }
    }

    private var listDetail: String {
        "Trafia na listę „\(payment.kind.reminderListName)” w aplikacji Przypomnienia."
    }

    private func doneHeadline(amount: Money) -> String {
        guard payment.kind.handlesMoney else { return payment.kind.doneLabel }
        return "\(payment.kind.doneLabel) \(amount.formatted(currencyCode: currencyCode))"
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
                Label(payment.kind.doneButton, systemImage: "checkmark")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    private var iconName: String {
        switch status {
        case .paid: return "checkmark.circle.fill"
        case .upcoming: return payment.kind == .incoming ? "arrow.down.circle" : "clock"
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
