import SwiftUI
import AppKit

// MARK: - Session cache

/// In-memory, session-scoped cache for related-paper lookups. Results are keyed
/// by `workId|relation` and never persisted — this keeps the discovery feature
/// off the SQLite write path and out of the recommendation pool. The user must
/// explicitly "Add to library" to materialize a paper.
@MainActor
@Observable
final class RelatedPapersStore {
    static let shared = RelatedPapersStore()

    enum Relation: String, CaseIterable {
        case similar
        case citedBy
    }

    private var cache: [String: [Paper]] = [:]

    private func key(_ workId: String, _ relation: Relation) -> String {
        "\(workId)|\(relation.rawValue)"
    }

    /// Returns a cached result without triggering a fetch, if present.
    func cached(_ workId: String, _ relation: Relation) -> [Paper]? {
        cache[key(workId, relation)]
    }

    /// Fetches (or returns the cached) related papers for a work.
    func load(workId: String, relation: Relation) async -> [Paper] {
        let k = key(workId, relation)
        if let hit = cache[k] { return hit }

        let config = ConfigManager.shared.effectiveConfig
        let fetcher = OpenAlexFetcher(config: config, venues: MetadataStore.shared.venues)

        let result: [Paper]
        switch relation {
        case .similar:  result = await fetcher.fetchSimilar(workId: workId)
        case .citedBy:  result = await fetcher.fetchCitedBy(workId: workId)
        }
        cache[k] = result
        return result
    }
}

// MARK: - Section view

struct RelatedPapersSection: View {
    let workId: String

    @State private var relation: RelatedPapersStore.Relation = .similar
    @State private var papers: [Paper] = []
    @State private var isLoading = false
    @State private var store = PaperStore.shared
    private var related: RelatedPapersStore { .shared }
    private var metadata: MetadataStore { .shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Image(systemName: "rectangle.stack")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                Text(L10n.t(.relatedPapers))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.primary)
            }

            Picker("", selection: $relation) {
                Text(L10n.t(.similarPapers)).tag(RelatedPapersStore.Relation.similar)
                Text(L10n.t(.citedBy)).tag(RelatedPapersStore.Relation.citedBy)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if isLoading {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(L10n.t(.loadingRelated))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            } else if papers.isEmpty {
                Text(L10n.t(.noRelated))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            } else {
                VStack(spacing: 6) {
                    ForEach(papers) { paper in
                        RelatedPaperRow(
                            paper: paper,
                            metadata: metadata,
                            inLibrary: store.papers.contains { $0.id == paper.id },
                            onAdd: { _ = PaperStore.shared.addOrUpdate(papers: [paper]) }
                        )
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .task(id: "\(workId)|\(relation.rawValue)") {
            await loadCurrent()
        }
    }

    private func loadCurrent() async {
        if let hit = related.cached(workId, relation) {
            papers = hit
            isLoading = false
            return
        }
        isLoading = true
        papers = []
        let result = await related.load(workId: workId, relation: relation)
        // `.task(id:)` cancels on paper/relation change; don't clobber the new state.
        if Task.isCancelled { return }
        papers = result
        isLoading = false
    }
}

// MARK: - Row

private struct RelatedPaperRow: View {
    let paper: Paper
    var metadata: MetadataStore
    let inLibrary: Bool
    let onAdd: () -> Void

    private var venueColor: Color {
        metadata.fieldColor(metadata.field(forAbbr: paper.venueAbbr))
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Button {
                if let url = URL(string: paper.landingPageUrl), url.scheme != nil {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(paper.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 6) {
                        if !paper.venueAbbr.isEmpty && paper.venueAbbr != "Others" {
                            Text(paper.venueAbbr)
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(venueColor.opacity(0.12))
                                .foregroundStyle(venueColor)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                        if let year = paper.publicationYear {
                            Text(String(year))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        Label("\(paper.citedByCount)", systemImage: "quote.opening")
                            .labelStyle(.titleAndIcon)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(paper.title)

            addButton
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(Color.gray.opacity(0.14), lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private var addButton: some View {
        if inLibrary {
            Label(L10n.t(.addedToLibrary), systemImage: "checkmark")
                .labelStyle(.iconOnly)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.green)
                .frame(width: 26, height: 26)
                .help(L10n.t(.addedToLibrary))
        } else {
            Button(action: onAdd) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 26, height: 26)
                    .background(Color.secondary.opacity(0.10))
                    .foregroundStyle(.primary.opacity(0.75))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 0.5)
                    )
            }
            .buttonStyle(.plain)
            .help(L10n.t(.addToLibrary))
        }
    }
}
