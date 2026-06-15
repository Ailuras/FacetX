import XCTest
@testable import VellumX

final class PaperReadingTimeTests: XCTestCase {

    private func paper(abstract: String) -> Paper {
        Paper(id: "W1", title: "t", abstract: abstract)
    }

    func testAbstractWordCountEmpty() {
        XCTAssertEqual(paper(abstract: "").abstractWordCount, 0)
        XCTAssertNil(paper(abstract: "").abstractReadingMinutes)
    }

    func testAbstractWordCountCountsTokens() {
        XCTAssertEqual(paper(abstract: "one two three").abstractWordCount, 3)
    }

    func testReadingMinutesRoundsUp() {
        // 1 word at 220 wpm ≈ 0.0045 min → ceiling clamps to 1.
        XCTAssertEqual(paper(abstract: "word").abstractReadingMinutes, 1)
    }

    func testReadingMinutesAtWpmBoundary() {
        // 221 words at 220 wpm should round up to 2.
        let words = Array(repeating: "word", count: 221).joined(separator: " ")
        XCTAssertEqual(paper(abstract: words).abstractReadingMinutes, 2)
    }

    func testReadingMinutesLargeAbstract() {
        // 1000 words / 220 wpm = 4.54 → ceil = 5.
        let words = Array(repeating: "word", count: 1000).joined(separator: " ")
        XCTAssertEqual(paper(abstract: words).abstractReadingMinutes, 5)
    }
}
