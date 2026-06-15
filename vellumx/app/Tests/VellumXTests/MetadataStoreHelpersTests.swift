import XCTest
@testable import VellumX

@MainActor
final class MetadataStoreHelpersTests: XCTestCase {

    // MARK: - normalizedField
    // "Others" / "OT" (any case) → nil; empty / nil → nil; other values pass through.

    func testNormalizedFieldOthersReturnsNil() {
        XCTAssertNil(MetadataStore.normalizedField("Others"))
    }

    func testNormalizedFieldOthersCaseInsensitive() {
        XCTAssertNil(MetadataStore.normalizedField("OTHERS"))
        XCTAssertNil(MetadataStore.normalizedField("others"))
        XCTAssertNil(MetadataStore.normalizedField("  Others  "))
    }

    func testNormalizedFieldOTReturnsNil() {
        XCTAssertNil(MetadataStore.normalizedField("OT"))
        XCTAssertNil(MetadataStore.normalizedField("ot"))
    }

    func testNormalizedFieldNilInputReturnsNil() {
        XCTAssertNil(MetadataStore.normalizedField(nil))
    }

    func testNormalizedFieldEmptyReturnsNil() {
        XCTAssertNil(MetadataStore.normalizedField(""))
        XCTAssertNil(MetadataStore.normalizedField("   "))
    }

    func testNormalizedFieldValidPassthrough() {
        XCTAssertEqual(MetadataStore.normalizedField("SE"), "SE")
        XCTAssertEqual(MetadataStore.normalizedField("  AI  "), "AI")
        XCTAssertEqual(MetadataStore.normalizedField("Formal Methods"), "Formal Methods")
    }

    // MARK: - normalizedFieldName
    // "OT" → nil; "Others" (any case) → canonical "Others"; empty → nil.

    func testNormalizedFieldNameOthersPreserved() {
        XCTAssertEqual(MetadataStore.normalizedFieldName("Others"), "Others")
    }

    func testNormalizedFieldNameOthersCaseNormalized() {
        // Case-insensitive match returns the canonical constant "Others", not the input.
        XCTAssertEqual(MetadataStore.normalizedFieldName("others"), "Others")
        XCTAssertEqual(MetadataStore.normalizedFieldName("OTHERS"), "Others")
    }

    func testNormalizedFieldNameOTReturnsNil() {
        XCTAssertNil(MetadataStore.normalizedFieldName("OT"))
        XCTAssertNil(MetadataStore.normalizedFieldName("ot"))
    }

    func testNormalizedFieldNameEmptyReturnsNil() {
        XCTAssertNil(MetadataStore.normalizedFieldName(""))
        XCTAssertNil(MetadataStore.normalizedFieldName(nil))
    }

    func testNormalizedFieldNameValidPassthrough() {
        XCTAssertEqual(MetadataStore.normalizedFieldName("SE"), "SE")
        XCTAssertEqual(MetadataStore.normalizedFieldName("  FM  "), "FM")
    }

    // MARK: - tierDefaultColor

    func testTierDefaultColorTier1IsRed() {
        XCTAssertEqual(MetadataStore.tierDefaultColor(1), .red)
    }

    func testTierDefaultColorTier2IsOrange() {
        XCTAssertEqual(MetadataStore.tierDefaultColor(2), .orange)
    }

    func testTierDefaultColorTier3IsYellow() {
        XCTAssertEqual(MetadataStore.tierDefaultColor(3), .yellow)
    }

    func testTierDefaultColorOtherIsGray() {
        XCTAssertEqual(MetadataStore.tierDefaultColor(0),  .gray)
        XCTAssertEqual(MetadataStore.tierDefaultColor(4),  .gray)
        XCTAssertEqual(MetadataStore.tierDefaultColor(-1), .gray)
        XCTAssertEqual(MetadataStore.tierDefaultColor(99), .gray)
    }

    // MARK: - defaultPoints

    func testDefaultPointsKnownTiers() {
        XCTAssertEqual(MetadataStore.defaultPoints(for: 1), 10)
        XCTAssertEqual(MetadataStore.defaultPoints(for: 2), 7)
        XCTAssertEqual(MetadataStore.defaultPoints(for: 3), 5)
        XCTAssertEqual(MetadataStore.defaultPoints(for: 4), 2)
        XCTAssertEqual(MetadataStore.defaultPoints(for: 5), 1)
    }

    func testDefaultPointsUnknownUsesFormula() {
        // rank 6 → max(1, 12 - 12) = 1
        XCTAssertEqual(MetadataStore.defaultPoints(for: 6), 1)
        // rank 7 → max(1, 12 - 14) = 1
        XCTAssertEqual(MetadataStore.defaultPoints(for: 7), 1)
    }

    func testDefaultPointsNegativeRankFormula() {
        // rank -1 → max(1, 12 - (-2)) = max(1, 14) = 14
        XCTAssertEqual(MetadataStore.defaultPoints(for: -1), 14)
    }
}
