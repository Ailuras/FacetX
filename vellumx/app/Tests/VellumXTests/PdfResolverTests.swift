import XCTest
@testable import VellumX

final class PdfResolverTests: XCTestCase {

    func testStripsHttpsDoi() {
        XCTAssertEqual(PdfResolver.stripDoiPrefix("https://doi.org/10.1145/123456"), "10.1145/123456")
    }

    func testStripsHttpDoi() {
        XCTAssertEqual(PdfResolver.stripDoiPrefix("http://doi.org/10.1145/123456"), "10.1145/123456")
    }

    func testStripsDxDoi() {
        XCTAssertEqual(PdfResolver.stripDoiPrefix("https://dx.doi.org/10.1007/s10270"), "10.1007/s10270")
    }

    func testStripsHttpDxDoi() {
        XCTAssertEqual(PdfResolver.stripDoiPrefix("http://dx.doi.org/10.1007/s10270"), "10.1007/s10270")
    }

    func testStripsCaseInsensitive() {
        XCTAssertEqual(PdfResolver.stripDoiPrefix("HTTPS://DOI.ORG/10.1145/123456"), "10.1145/123456")
        XCTAssertEqual(PdfResolver.stripDoiPrefix("Https://Doi.Org/10.1145/xyz"), "10.1145/xyz")
    }

    func testBareDOIUnchanged() {
        XCTAssertEqual(PdfResolver.stripDoiPrefix("10.1145/123456"), "10.1145/123456")
        XCTAssertEqual(PdfResolver.stripDoiPrefix("10.1007/s10270-023-01032-z"), "10.1007/s10270-023-01032-z")
    }

    func testEmptyStringUnchanged() {
        XCTAssertEqual(PdfResolver.stripDoiPrefix(""), "")
    }

    func testUnrelatedURLUnchanged() {
        let url = "https://arxiv.org/abs/2301.00001"
        XCTAssertEqual(PdfResolver.stripDoiPrefix(url), url)
    }
}
