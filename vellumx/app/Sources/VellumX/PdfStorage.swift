import Foundation
import CryptoKit
import AppKit

/// Lifecycle of a paper's PDF as derived secondary data.
/// - `downloaded`: a validated PDF is stored locally and readable offline.
/// - `notPdf`: the resolved link returned content that is not a PDF (landing
///   page / paywall HTML); nothing is stored.
/// - `dead`: no open-access link could be resolved.
enum PdfStatus: String {
    case downloaded
    case notPdf = "not_pdf"
    case dead
}

/// Outcome of resolving + downloading a paper's PDF. PDF binaries are
/// "derived but materialized" data: their provenance is the paper metadata
/// (via `PdfResolver`), but once downloaded they are kept as first-class
/// assets because open-access links rot over time.
struct PdfFetchResult {
    var status: PdfStatus
    /// Source link. Present for `.downloaded` and `.notPdf`.
    var url: String?
    /// Resolver that produced the link: unpaywall / arxiv / semanticscholar / openalex.
    var source: String?
    /// Relative path under the storage directory, e.g. `pdfs/W123.pdf`.
    /// Present only for `.downloaded`.
    var localPath: String?
    var byteSize: Int?
    var sha256: String?

    static let dead = PdfFetchResult(status: .dead)

    static func notPdf(url: String, source: String) -> PdfFetchResult {
        PdfFetchResult(status: .notPdf, url: url, source: source)
    }
}

/// Filesystem home for downloaded PDFs. Files are flat under `<storage>/pdfs/`
/// and named by the paper's OpenAlex id, so a path is a pure function of the
/// primary key — no opaque mapping table is needed to locate a file.
struct PdfStorage {
    /// The library root (holds `vellumx.db`). Captured at construction so the
    /// struct can be used off the main actor; build it via `current()`.
    let baseDirectory: URL

    /// Builds a storage rooted at the active library directory. Must be called
    /// on the main actor because it reads `AppSettings.shared`.
    @MainActor
    static func current() -> PdfStorage {
        PdfStorage(baseDirectory: AppSettings.shared.resolvedStorageDirectory)
    }

    /// `<baseDirectory>/pdfs`.
    var pdfsDirectory: URL {
        baseDirectory.appendingPathComponent("pdfs")
    }

    /// Absolute URL for a stored relative path (`pdfs/W123.pdf`).
    func absoluteURL(forRelative relative: String) -> URL {
        baseDirectory.appendingPathComponent(relative)
    }

    func fileExists(relative: String) -> Bool {
        FileManager.default.fileExists(atPath: absoluteURL(forRelative: relative).path)
    }

    /// Reveals the stored file in Finder with it selected. Returns false when
    /// the file is missing so the caller can fall back (e.g. re-fetch).
    @discardableResult
    func revealInFinder(relative: String) -> Bool {
        guard fileExists(relative: relative) else { return false }
        NSWorkspace.shared.activateFileViewerSelecting([absoluteURL(forRelative: relative)])
        return true
    }

    /// Writes PDF bytes for a paper and returns the stored relative path.
    @discardableResult
    func write(_ data: Data, forPaperId id: String) throws -> String {
        let dir = pdfsDirectory
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let name = "\(Self.bareOpenAlexId(id)).pdf"
        let dest = dir.appendingPathComponent(name)
        try data.write(to: dest, options: .atomic)
        return "pdfs/\(name)"
    }

    func delete(relative: String) {
        try? FileManager.default.removeItem(at: absoluteURL(forRelative: relative))
    }

    // MARK: - Pure helpers

    /// Strips the OpenAlex URL prefix and sanitizes the id into a filename-safe
    /// token. Falls back to a SHA-256 hex digest for ids that sanitize to empty
    /// (e.g. manually added papers without an OpenAlex id).
    static func bareOpenAlexId(_ id: String) -> String {
        var work = id
        for prefix in ["https://openalex.org/", "http://openalex.org/"] {
            if work.lowercased().hasPrefix(prefix) {
                work = String(work.dropFirst(prefix.count))
                break
            }
        }
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
        let sanitized = String(work.filter { allowed.contains($0) })
        if !sanitized.isEmpty { return sanitized }
        let digest = SHA256.hash(data: Data(id.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// True when the bytes begin with the PDF magic marker `%PDF-`. This is the
    /// authoritative check for "is this actually a PDF" — content-type headers
    /// lie, but a landing page / paywall HTML never starts with `%PDF-`.
    static func looksLikePdf(_ data: Data) -> Bool {
        let magic: [UInt8] = [0x25, 0x50, 0x44, 0x46, 0x2D] // "%PDF-"
        guard data.count >= magic.count else { return false }
        return Array(data.prefix(magic.count)) == magic
    }

    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
