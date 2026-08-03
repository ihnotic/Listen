import XCTest
@testable import Listen

final class TranscriptionModelTests: XCTestCase {
    func testFreshInstallDefaultsToUnifiedEnglish() {
        XCTAssertEqual(TranscriptionModel.fromPersistedValue(nil), .parakeetUnifiedEnglish)
    }

    func testLegacyParakeetPreferenceMigratesToMultilingualV3() {
        XCTAssertEqual(
            TranscriptionModel.fromPersistedValue("parakeet-tdt-0.6b"),
            .parakeetV3Multilingual
        )
    }

    func testUnknownPreferenceFallsBackToUnifiedEnglish() {
        XCTAssertEqual(TranscriptionModel.fromPersistedValue("unknown-model"), .parakeetUnifiedEnglish)
    }

    func testAppleSpeechIsOnlyOfferedOnMacOS26AndLater() {
        XCTAssertEqual(
            TranscriptionModel.availableModels(macOSMajorVersion: 14),
            [.parakeetUnifiedEnglish, .parakeetV3Multilingual]
        )
        XCTAssertEqual(
            TranscriptionModel.availableModels(macOSMajorVersion: 26),
            [.parakeetUnifiedEnglish, .parakeetV3Multilingual, .appleSpeechAnalyzer]
        )
    }

    func testStablePersistedIdentifiers() {
        XCTAssertEqual(TranscriptionModel.parakeetUnifiedEnglish.rawValue, "parakeet-unified-en-0.6b")
        XCTAssertEqual(TranscriptionModel.parakeetV3Multilingual.rawValue, "parakeet-tdt-0.6b-v3")
        XCTAssertEqual(TranscriptionModel.appleSpeechAnalyzer.rawValue, "apple-speech-analyzer")
    }
}
