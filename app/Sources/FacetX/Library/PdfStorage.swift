import Foundation
import CryptoKit
import AppKit

enum PdfStatus: String {
    case downloaded
    case notPdf = "not_pdf"
    case dead
}

struct PdfFetchResult {
    var status: PdfStatus
    var url: String?
    var source: String?
    var localPath: String?
    var byteSize: Int?
    var sha256: String?

    static let dead = PdfFetchResult(status: .dead)

    static func notPdf(url: String, source: String) -> PdfFetchResult {
        PdfFetchResult(status: .notPdf, url: url, source: source)
    }
}

struct PdfStorage {
    let baseDirectory: URL

    @MainActor
    static func current() -> PdfStorage {
        PdfStorage(baseDirectory: LibrarySettings.shared.resolvedStorageDirectory)
    }

    var pdfsDirectory: URL {
        baseDirectory.appendingPathComponent("pdfs")
    }

    func absoluteURL(forRelative relative: String) -> URL {
        baseDirectory.appendingPathComponent(relative)
    }

    func fileExists(relative: String) -> Bool {
        FileManager.default.fileExists(atPath: absoluteURL(forRelative: relative).path)
    }

    @discardableResult
    func revealInFinder(relative: String) -> Bool {
        guard fileExists(relative: relative) else { return false }
        NSWorkspace.shared.activateFileViewerSelecting([absoluteURL(forRelative: relative)])
        return true
    }

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

    static func looksLikePdf(_ data: Data) -> Bool {
        let magic: [UInt8] = [0x25, 0x50, 0x44, 0x46, 0x2D] // "%PDF-"
        guard data.count >= magic.count else { return false }
        return Array(data.prefix(magic.count)) == magic
    }

    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
