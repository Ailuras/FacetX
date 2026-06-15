import Foundation

/// UI-facing bridge for PDF actions. Keeps the two user intents separate —
/// *fetching* a PDF and *revealing* an already-downloaded one — and owns the
/// app-state side effects (persistence + toasts) that the pure `PdfFetcher`
/// deliberately avoids.
@MainActor
enum PdfCoordinator {

    /// True when the paper has a validated PDF stored on disk.
    static func hasLocalPdf(_ paper: Paper) -> Bool {
        guard let path = paper.pdfLocalPath, !path.isEmpty else { return false }
        return PdfStorage.current().fileExists(relative: path)
    }

    /// Resolves and downloads a PDF, persists the outcome, and reports it via a
    /// toast. Does not open anything — fetching and opening are distinct actions.
    static func fetch(paper: Paper, store: PaperStore) async {
        let storage = PdfStorage.current()
        let config = ConfigManager.shared.effectiveConfig

        NotificationCenter.shared.setStatus(L10n.t(.resolvingPDF), type: .progress)
        let result = await PdfFetcher(config: config, storage: storage)
            .fetch(id: paper.id, title: paper.title, doi: paper.doi, currentPdfUrl: paper.pdfUrl)

        // If a previous local PDF exists but the new result is not a download,
        // remove the orphaned file so the library stays consistent.
        if result.status != .downloaded, let oldPath = paper.pdfLocalPath {
            storage.delete(relative: oldPath)
        }

        store.savePdf(id: paper.id, result: result)
        NotificationCenter.shared.clearStatus()

        switch result.status {
        case .downloaded:
            NotificationCenter.shared.showToast(L10n.t(.pdfDownloaded), type: .success)
        case .notPdf:
            NotificationCenter.shared.showToast(L10n.t(.pdfNotAvailable), type: .warning)
        case .dead:
            NotificationCenter.shared.showToast(L10n.t(.pdfNotFound), type: .error)
        }
    }

    /// Reveals the downloaded PDF in Finder with it selected. If the file is
    /// missing (e.g. deleted out of band), re-fetches it instead.
    static func reveal(paper: Paper, store: PaperStore) async {
        if let path = paper.pdfLocalPath, PdfStorage.current().revealInFinder(relative: path) {
            return
        }
        await fetch(paper: paper, store: store)
    }

    /// Copies a user-chosen PDF into the structured library, validating it first.
    /// The manual PDF lands in the same place as a downloaded one
    /// (`pdfs/<id>.pdf`, source "manual"), so reveal/migration/shared-library
    /// behavior applies uniformly.
    static func setManualPdf(paper: Paper, store: PaperStore, from fileURL: URL) {
        // A dropped or sandbox-scoped file URL needs explicit access to read.
        let scoped = fileURL.startAccessingSecurityScopedResource()
        defer { if scoped { fileURL.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: fileURL) else {
            NotificationCenter.shared.showToast(L10n.t(.pdfSetFailed), type: .error)
            return
        }
        guard PdfStorage.looksLikePdf(data) else {
            NotificationCenter.shared.showToast(L10n.t(.notAPdfFile), type: .warning)
            return
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
            NotificationCenter.shared.showToast(L10n.t(.pdfSet), type: .success)
        } catch {
            NotificationCenter.shared.showToast(L10n.t(.pdfSetFailed), type: .error)
        }
    }

    /// Deletes the stored file (if any) and clears the paper's PDF record.
    static func removePdf(paper: Paper, store: PaperStore) {
        if let path = paper.pdfLocalPath {
            PdfStorage.current().delete(relative: path)
        }
        store.removePdf(id: paper.id)
        NotificationCenter.shared.showToast(L10n.t(.pdfRemoved), type: .info)
    }
}
