import XCTest
@testable import VellumX

@MainActor
final class PaperStoreHelpersTests: XCTestCase {

    // MARK: - splitCSV

    func testSplitCSVBasic() {
        XCTAssertEqual(PaperStore.splitCSV("a, b, c"), ["a", "b", "c"])
    }

    func testSplitCSVTrimsWhitespace() {
        XCTAssertEqual(PaperStore.splitCSV("  foo ,  bar  "), ["foo", "bar"])
    }

    func testSplitCSVFiltersEmpty() {
        XCTAssertEqual(PaperStore.splitCSV("a,,b"), ["a", "b"])
    }

    func testSplitCSVEmptyInput() {
        XCTAssert(PaperStore.splitCSV("").isEmpty)
    }

    func testSplitCSVOnlyCommas() {
        XCTAssert(PaperStore.splitCSV(",,").isEmpty)
    }

    func testSplitCSVSingleToken() {
        XCTAssertEqual(PaperStore.splitCSV("hello"), ["hello"])
    }

    func testSplitCSVOnlyWhitespace() {
        XCTAssert(PaperStore.splitCSV("   ").isEmpty)
    }

    // MARK: - normalizedTag

    func testNormalizedTagStripsHash() {
        XCTAssertEqual(PaperStore.normalizedTag("#foo"), "foo")
    }

    func testNormalizedTagStripsMultipleHashes() {
        XCTAssertEqual(PaperStore.normalizedTag("##foo"), "foo")
        XCTAssertEqual(PaperStore.normalizedTag("# # #bar"), "bar")
    }

    func testNormalizedTagTrimsSpaces() {
        XCTAssertEqual(PaperStore.normalizedTag("  foo  "), "foo")
        XCTAssertEqual(PaperStore.normalizedTag("  #  foo  "), "foo")
    }

    func testNormalizedTagOnlyHashReturnsNil() {
        XCTAssertNil(PaperStore.normalizedTag("#"))
        XCTAssertNil(PaperStore.normalizedTag("##"))
        XCTAssertNil(PaperStore.normalizedTag("# # #"))
    }

    func testNormalizedTagEmptyReturnsNil() {
        XCTAssertNil(PaperStore.normalizedTag(""))
        XCTAssertNil(PaperStore.normalizedTag("   "))
    }

    // MARK: - parseSQLiteDate

    func testParseSQLiteDateValid() throws {
        let date = try XCTUnwrap(PaperStore.parseSQLiteDate("2024-01-15 12:30:00"))
        let components = Calendar(identifier: .gregorian)
            .dateComponents(in: TimeZone(secondsFromGMT: 0)!, from: date)
        XCTAssertEqual(components.year, 2024)
        XCTAssertEqual(components.month, 1)
        XCTAssertEqual(components.day, 15)
        XCTAssertEqual(components.hour, 12)
        XCTAssertEqual(components.minute, 30)
    }

    func testParseSQLiteDateInvalidFormat() {
        XCTAssertNil(PaperStore.parseSQLiteDate("2024-01-15"))   // date-only, missing time
    }

    func testParseSQLiteDateEmpty() {
        XCTAssertNil(PaperStore.parseSQLiteDate(""))
    }

    func testParseSQLiteDateGarbageInput() {
        XCTAssertNil(PaperStore.parseSQLiteDate("not a date"))
    }
}
