import XCTest

final class PersistenceTests: XCTestCase {
    private var directory: URL!
    private var repository: FilePaymentRepository!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlatnosciTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        repository = FilePaymentRepository(
            fileURL: directory.appendingPathComponent("payments.json")
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testLoadingMissingFileGivesEmptySnapshot() throws {
        XCTAssertEqual(try repository.load(), .empty)
    }

    func testRoundTripPreservesEverything() throws {
        let payment = TestSupport.payment(name: "Marek", amount: 300, dueDay: 12)
        let entry = TestSupport.entry(
            for: payment,
            period: MonthKey(year: 2026, month: 8),
            paidAt: TestSupport.date(year: 2026, month: 8, day: 12, hour: 14)
        )
        let snapshot = PaymentsSnapshot(
            payments: [payment],
            entries: [entry],
            settings: AppSettings(
                currencyCode: "PLN",
                lookaheadMonths: 2,
                didSeedExamples: true
            )
        )

        try repository.save(snapshot)
        let loaded = try repository.load()

        XCTAssertEqual(loaded, snapshot)
        XCTAssertEqual(loaded.payments.first?.amount.value, 300)
        XCTAssertEqual(loaded.entries.first?.paymentName, "Marek")
        XCTAssertTrue(loaded.settings.didSeedExamples)
    }

    func testSaveAlwaysStampsCurrentSchemaVersion() throws {
        var snapshot = PaymentsSnapshot.empty
        snapshot.schemaVersion = 0

        try repository.save(snapshot)

        XCTAssertEqual(
            try repository.load().schemaVersion,
            PaymentsSnapshot.currentSchemaVersion
        )
    }

    /// Test regresyjny na najgroźniejszy błąd pierwszej wersji: odczyt używał
    /// `try?` i przy nieudanym dekodowaniu po cichu zwracał pustkę, czyli gubił
    /// całą historię. Teraz błąd jest zgłaszany, a uszkodzony plik odkładany.
    func testCorruptedFileIsReportedAndQuarantined() throws {
        let fileURL = directory.appendingPathComponent("payments.json")
        try Data("to nie jest JSON".utf8).write(to: fileURL)

        XCTAssertThrowsError(try repository.load()) { error in
            guard case RepositoryError.corruptedStore(let backupURL, _) = error else {
                return XCTFail("Oczekiwano RepositoryError.corruptedStore, otrzymano \(error)")
            }
            XCTAssertNotNil(backupURL, "Uszkodzony plik musi zostać odłożony, nie usunięty")
            if let backupURL {
                XCTAssertTrue(FileManager.default.fileExists(atPath: backupURL.path))
            }
        }

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: fileURL.path),
            "Uszkodzony plik nie może zostać na swoim miejscu"
        )
    }

    /// Dodanie nowego pola w przyszłej wersji nie może wysypać dekodowania
    /// starych danych. Dlatego modele mają ręczne dekodery z wartościami
    /// domyślnymi, zamiast polegać na syntezie.
    func testDecodingMinimalJSONFillsInDefaults() throws {
        let json = """
        {
          "schemaVersion": 1,
          "payments": [
            {
              "id": "8E4E2C4E-0000-4000-8000-000000000001",
              "name": "Stara płatność",
              "amount": 250
            }
          ],
          "entries": []
        }
        """

        let snapshot = try JSONDecoder().decode(
            PaymentsSnapshot.self,
            from: Data(json.utf8)
        )

        let payment = try XCTUnwrap(snapshot.payments.first)
        XCTAssertEqual(payment.name, "Stara płatność")
        XCTAssertEqual(payment.amount.value, 250)
        XCTAssertEqual(payment.dueDay, 10)
        XCTAssertEqual(payment.reminderTime, .morning)
        XCTAssertEqual(payment.intensity, .persistent)
        XCTAssertTrue(payment.isActive)
        XCTAssertEqual(payment.note, "")
        XCTAssertEqual(snapshot.settings, .default)
    }

    func testOverwritingKeepsFileValid() throws {
        try repository.save(PaymentsSnapshot.empty)

        var snapshot = try repository.load()
        snapshot.payments = [TestSupport.payment(name: "Nowa")]
        try repository.save(snapshot)

        XCTAssertEqual(try repository.load().payments.map(\.name), ["Nowa"])
    }

    func testMigrationRaisesSchemaVersion() {
        var snapshot = PaymentsSnapshot.empty
        snapshot.schemaVersion = 0

        XCTAssertEqual(
            snapshot.migratedToCurrentSchema().schemaVersion,
            PaymentsSnapshot.currentSchemaVersion
        )
    }

    func testDueDayIsClampedOnDecode() throws {
        let json = """
        {
          "payments": [
            {
              "id": "8E4E2C4E-0000-4000-8000-000000000002",
              "name": "Zły dzień",
              "amount": 10,
              "dueDay": 99
            }
          ]
        }
        """

        let snapshot = try JSONDecoder().decode(
            PaymentsSnapshot.self,
            from: Data(json.utf8)
        )

        XCTAssertEqual(snapshot.payments.first?.dueDay, 31)
    }
}
