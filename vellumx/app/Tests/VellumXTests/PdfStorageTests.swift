import XCTest
@testable import VellumX

final class PdfStorageTests: XCTestCase {

    // MARK: - bareOpenAlexId

    func testStripsOpenAlexPrefix() {
        XCTAssertEqual(PdfStorage.bareOpenAlexId("https://openalex.org/W2741809807"), "W2741809807")
        XCTAssertEqual(PdfStorage.bareOpenAlexId("http://openalex.org/W123"), "W123")
    }

    func testBareIdUnchangedWhenAlreadyBare() {
        XCTAssertEqual(PdfStorage.bareOpenAlexId("W2741809807"), "W2741809807")
    }

    func testSanitizesUnsafeCharacters() {
        // Path separators / spaces are stripped so the result is filename-safe.
        XCTAssertEqual(PdfStorage.bareOpenAlexId("https://openalex.org/W12/../x y"), "W12xy")
        XCTAssertFalse(PdfStorage.bareOpenAlexId("a/b c:d").contains(where: { "/ :".contains($0) }))
    }

    func testFallsBackToHashWhenSanitizedEmpty() {
        // An id that sanitizes to empty yields a stable 64-char SHA-256 hex.
        let hash = PdfStorage.bareOpenAlexId("/// :::")
        XCTAssertEqual(hash.count, 64)
        XCTAssertEqual(hash, PdfStorage.bareOpenAlexId("/// :::"))
    }

    // MARK: - looksLikePdf

    func testRealPdfMagicBytes() {
        XCTAssertTrue(PdfStorage.looksLikePdf(Data("%PDF-1.7\n…".utf8)))
    }

    func testHtmlIsNotPdf() {
        XCTAssertFalse(PdfStorage.looksLikePdf(Data("<!DOCTYPE html><html>".utf8)))
    }

    func testEmptyAndShortDataAreNotPdf() {
        XCTAssertFalse(PdfStorage.looksLikePdf(Data()))
        XCTAssertFalse(PdfStorage.looksLikePdf(Data("%PD".utf8)))
    }

    // MARK: - PdfStatus

    func testStatusRawValues() {
        XCTAssertEqual(PdfStatus.notPdf.rawValue, "not_pdf")
        XCTAssertEqual(PdfStatus(rawValue: "downloaded"), .downloaded)
        XCTAssertEqual(PdfStatus(rawValue: "dead"), .dead)
    }
}
