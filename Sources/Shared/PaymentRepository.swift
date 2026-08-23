import Foundation

enum RepositoryError: Error, LocalizedError {
    /// Plik istniał, ale nie dał się odczytać. Uszkodzona kopia została odłożona
    /// na bok pod podaną ścieżką, żeby dane nie przepadły bezpowrotnie.
    case corruptedStore(backupURL: URL?, underlying: Error)

    var errorDescription: String? {
        switch self {
        case .corruptedStore(let backupURL, _):
            if let backupURL {
                return "Nie udało się odczytać danych. Kopia uszkodzonego pliku: \(backupURL.lastPathComponent)."
            }
            return "Nie udało się odczytać danych."
        }
    }
}

protocol PaymentRepository: Sendable {
    func load() throws -> PaymentsSnapshot
    func save(_ snapshot: PaymentsSnapshot) throws
}

/// Zapis do jednego pliku JSON.
///
/// Świadomie nie używamy `UserDefaults` (jak pierwsza wersja): plik jest
/// zapisywany atomowo, da się go podejrzeć i naprawić, a przy uszkodzeniu
/// odkładamy kopię zamiast po cichu zwracać pustkę.
struct FilePaymentRepository: PaymentRepository {
    let fileURL: URL

    init(fileURL: URL = StorageLocation.storeFileURL()) {
        self.fileURL = fileURL
    }

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    func load() throws -> PaymentsSnapshot {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .empty
        }

        let data = try Data(contentsOf: fileURL)

        do {
            return try decoder.decode(PaymentsSnapshot.self, from: data)
                .migratedToCurrentSchema()
        } catch {
            throw RepositoryError.corruptedStore(
                backupURL: quarantineCorruptedFile(),
                underlying: error
            )
        }
    }

    func save(_ snapshot: PaymentsSnapshot) throws {
        var toWrite = snapshot
        toWrite.schemaVersion = PaymentsSnapshot.currentSchemaVersion

        let data = try encoder.encode(toWrite)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: [.atomic])
    }

    private func quarantineCorruptedFile() -> URL? {
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let backupURL = fileURL
            .deletingLastPathComponent()
            .appendingPathComponent("uszkodzony-\(stamp).json")
        do {
            try FileManager.default.moveItem(at: fileURL, to: backupURL)
            return backupURL
        } catch {
            return nil
        }
    }
}
