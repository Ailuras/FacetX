import Foundation
import Observation

struct PaperWorkflowResult {
    var didRun: Bool
    var message: String
    var toastType: ToastType
}

@MainActor
@Observable
final class PaperWorkflowService {
    static let shared = PaperWorkflowService()

    var isFetching = false
    var isRecommending = false

    var isBusy: Bool { isFetching || isRecommending }

    private init() {}

    func fetchPapers(notify: Bool = true) async -> PaperWorkflowResult {
        guard !isBusy else {
            return report("Another paper workflow is already running.", type: .info, notify: notify)
        }

        let config = ConfigManager.shared.effectiveConfig
        guard !config.tracks.isEmpty else {
            return report("No tracks configured - add one in Settings > Rules", type: .warning, notify: notify)
        }

        isFetching = true
        if notify {
            NotificationCenter.shared.setStatus("Fetching OpenAlex papers...", type: .progress)
        }
        defer {
            if notify { NotificationCenter.shared.clearStatus() }
            isFetching = false
        }

        do {
            let fetcher = OpenAlexFetcher(config: config, venues: MetadataStore.shared.venues)
            let result = try await fetcher.fetch()
            let stats = PaperStore.shared.addOrUpdate(papers: result.papers)
            let message = fetchStatusMessage(
                inserted: stats.inserted,
                updated: stats.updated,
                failedTracks: result.failedTracks
            )
            if notify {
                NotificationCenter.shared.showToast(message, type: .success)
            }
            return PaperWorkflowResult(didRun: true, message: message, toastType: .success)
        } catch {
            let message = "Fetch failed: \(error.localizedDescription)"
            if notify {
                NotificationCenter.shared.showToast(message, type: .error)
            }
            return PaperWorkflowResult(didRun: false, message: message, toastType: .error)
        }
    }

    func recommendPapers(notify: Bool = true) async -> PaperWorkflowResult {
        guard !isBusy else {
            return report("Another paper workflow is already running.", type: .info, notify: notify)
        }

        isRecommending = true
        if notify {
            NotificationCenter.shared.setStatus("Running recommendation engine...", type: .progress)
        }
        defer {
            if notify { NotificationCenter.shared.clearStatus() }
            isRecommending = false
        }

        let engine = RecommendEngine(config: ConfigManager.shared.effectiveConfig)
        let selected = engine.recommend(papers: PaperStore.shared.papers)
        for result in selected {
            PaperStore.shared.setPaperRecommended(id: result.paper.id, isRecommended: true, reason: result.reason)
        }

        let message = selected.isEmpty
            ? "No new candidates to recommend."
            : "Added \(selected.count) new recommendations!"
        let type: ToastType = selected.isEmpty ? .info : .success
        if notify {
            NotificationCenter.shared.showToast(message, type: type)
        }
        return PaperWorkflowResult(didRun: true, message: message, toastType: type)
    }

    private func report(_ message: String, type: ToastType, notify: Bool) -> PaperWorkflowResult {
        if notify {
            NotificationCenter.shared.showToast(message, type: type)
        }
        return PaperWorkflowResult(didRun: false, message: message, toastType: type)
    }

    private func fetchStatusMessage(inserted: Int, updated: Int, failedTracks: [String]) -> String {
        let base = "Fetched! Added \(inserted) | Updated \(updated)"
        guard !failedTracks.isEmpty else { return base }
        return "\(base) | Failed: \(failedTracks.joined(separator: ", "))"
    }
}
