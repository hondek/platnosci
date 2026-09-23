import SwiftUI
import WidgetKit

/// Widget na ekran główny i ekran blokady.
///
/// Buduje się tylko przy specyfikacji `project.widget.yml` i wymaga płatnego
/// konta Apple Developer — widget jest osobnym procesem i czyta dane aplikacji
/// wyłącznie przez App Groups, a darmowe Apple ID nie dostaje tego uprawnienia.
///
/// To jedyny element iOS, który naprawdę jest „cały czas na wierzchu": raz
/// dodany na ekran blokady wisi tam bezterminowo, bez możliwości przypadkowego
/// zamknięcia.
struct UnpaidEntry: TimelineEntry {
    let date: Date
    let unpaidCount: Int
    let totalCount: Int
    let remaining: Money
    let currencyCode: String
    let nextName: String?
    let hasSharedData: Bool
}

struct UnpaidProvider: TimelineProvider {
    func placeholder(in context: Context) -> UnpaidEntry {
        UnpaidEntry(
            date: Date(),
            unpaidCount: 2,
            totalCount: 3,
            remaining: Money(2300),
            currencyCode: "PLN",
            nextName: "Marek",
            hasSharedData: true
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (UnpaidEntry) -> Void) {
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UnpaidEntry>) -> Void) {
        let entry = currentEntry()
        // Odświeżamy co godzinę: dane zmienia aplikacja, a widget nie dostaje
        // o tym powiadomienia, jeśli aplikacja nie zdąży wywołać reloadTimelines.
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func currentEntry() -> UnpaidEntry {
        guard StorageLocation.isUsingSharedContainer,
              let snapshot = try? FilePaymentRepository().load()
        else {
            return UnpaidEntry(
                date: Date(),
                unpaidCount: 0,
                totalCount: 0,
                remaining: .zero,
                currencyCode: "PLN",
                nextName: nil,
                hasSharedData: false
            )
        }

        let calendar = Calendar.current
        let period = MonthKey(date: Date(), calendar: calendar)
        let outgoing = snapshot.payments.filter { $0.kind == .outgoing }
        let unpaid = PaymentsEngine.unpaid(
            payments: outgoing,
            period: period,
            entries: snapshot.entries
        )
        let summary = PaymentsEngine.summary(
            payments: outgoing,
            period: period,
            entries: snapshot.entries
        )

        let soonest = unpaid.min { $0.dueDay < $1.dueDay }

        return UnpaidEntry(
            date: Date(),
            unpaidCount: unpaid.count,
            totalCount: summary.totalCount,
            remaining: summary.remaining,
            currencyCode: snapshot.settings.currencyCode,
            nextName: soonest?.name,
            hasSharedData: true
        )
    }
}

struct UnpaidWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: UnpaidEntry

    var body: some View {
        switch family {
        case .accessoryInline:
            Text(inlineText)

        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Text("\(entry.unpaidCount)")
                        .font(.title2.bold())
                    Text("do zapł.")
                        .font(.system(size: 8))
                }
            }

        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text(headline)
                    .font(.headline)
                Text(entry.remaining.formatted(currencyCode: entry.currencyCode))
                    .font(.caption)
                if let name = entry.nextName {
                    Text(name)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

        default:
            VStack(alignment: .leading, spacing: 6) {
                Text(headline)
                    .font(.headline)
                Text(entry.remaining.formatted(currencyCode: entry.currencyCode))
                    .font(.title3.bold())
                    .foregroundStyle(entry.unpaidCount > 0 ? .orange : .green)
                if let name = entry.nextName {
                    Text("Najbliższa: \(name)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var headline: String {
        guard entry.hasSharedData else { return "Otwórz aplikację" }
        if entry.totalCount == 0 { return "Brak płatności" }
        if entry.unpaidCount == 0 { return "Wszystko opłacone" }
        return "\(entry.unpaidCount) do zapłaty"
    }

    private var inlineText: String {
        guard entry.hasSharedData else { return "Płatności" }
        if entry.unpaidCount == 0 { return "Opłacone" }
        return "\(entry.unpaidCount) do zapłaty"
    }
}

struct UnpaidWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PlatnosciUnpaid", provider: UnpaidProvider()) { entry in
            UnpaidWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Do zapłaty")
        .description("Liczba i suma nieopłaconych płatności w tym miesiącu.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryInline,
            .accessoryCircular,
            .accessoryRectangular
        ])
    }
}

@main
struct PlatnosciWidgetBundle: WidgetBundle {
    var body: some Widget {
        UnpaidWidget()
    }
}
