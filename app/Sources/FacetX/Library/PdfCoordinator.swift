import Foundation

/// UI-facing bridge for PDF actions. Keeps fetching, revealing, manual attach,
/// and removal separate so each button does exactly what it advertises.
@MainActor
enum PdfCoordinator {

    static func hasLocalPdf(_ paper: Paper) -> Bool {
        guard let path = paper.pdfLocalPath, !path.isEmpty else { return false }
        return PdfStorage.current().fileExists(relative: path)
    }

    /// Reveals the downloaded PDF in Finder. Returns false if the file is missing.
    static func reveal(paper: Paper) -> Bool {
        guard let path = paper.pdfLocalPath else { return false }
        return PdfStorage.current().revealInFinder(relative: path)
    }

    /// Resolves and downloads an open-access PDF, persists the outcome, and
    /// returns the materialized status for the caller to present.
    static func fetch(paper: Paper, store: PaperStore) async -> PdfFetchResult {
        let storage = PdfStorage.current()
        let result = await PdfFetcher(
            config: ConfigManager.shared.effectiveConfig,
            storage: storage
        ).fetch(
            id: paper.id,
            title: paper.title,
            doi: paper.doi,
            currentPdfUrl: paper.pdfUrl
        )

        if result.status != .downloaded, let oldPath = paper.pdfLocalPath {
            storage.delete(relative: oldPath)
        }
        store.savePdf(id: paper.id, result: result)
        return result
    }

    /// Copies a user-chosen PDF into the structured library, validating it first.
    /// Returns a result message appropriate for a toast.
    enum SetResult {
        case success
        case notPDF
        case failed
    }

    static func setManualPdf(paper: Paper, store: PaperStore, from fileURL: URL) -> SetResult {
        let scoped = fileURL.startAccessingSecurityScopedResource()
        defer { if scoped { fileURL.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: fileURL) else {
            return .failed
        }
        guard PdfStorage.looksLikePdf(data) else {
            return .notPDF
        }
        do {
            let relative = try PdfStorage.current().write(data, forPaperId: paper.id)
            store.savePdf(id: paper.id, result: PdfFetchResult(
                status: .downloaded,
                url: nil,
                source: "manual",
                localPath: relative,
                byteSize: data.count,
                sha256: PdfStorage.sha256Hex(data)
            ))
            return .success
        } catch {
            return .failed
        }
    }

    /// Deletes the stored file (if any) and clears the paper's PDF record.
    static func removePdf(paper: Paper, store: PaperStore) {
        if let path = paper.pdfLocalPath {
            PdfStorage.current().delete(relative: path)
        }
        store.removePdf(id: paper.id)
    }
}
