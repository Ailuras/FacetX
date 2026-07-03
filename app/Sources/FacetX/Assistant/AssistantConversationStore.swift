import Foundation

struct AssistantConversationSummary: Identifiable, Equatable {
    let id: UUID
    let title: String
    let updatedAt: Date
    let provider: TranslationProvider
    let model: String
}

struct StoredAssistantConversation: Codable {
    let id: UUID
    var title: String
    let createdAt: Date
    var updatedAt: Date
    var provider: TranslationProvider
    var model: String
    var baseURL: String
    var entries: [AssistantEntry]
    var apiMessages: Data
    var totalInputTokens: Int
    var totalOutputTokens: Int

    var summary: AssistantConversationSummary {
        AssistantConversationSummary(
            id: id,
            title: title,
            updatedAt: updatedAt,
            provider: provider,
            model: model
        )
    }
}

@MainActor
final class AssistantConversationStore {
    private let url = AppSupport.directory().appendingPathComponent("assistant-conversations.json")
    private(set) var records: [StoredAssistantConversation]

    init() {
        records = (try? Data(contentsOf: url))
            .flatMap { try? JSONDecoder().decode([StoredAssistantConversation].self, from: $0) }
            ?? []
        sort()
    }

    func record(id: UUID) -> StoredAssistantConversation? {
        records.first { $0.id == id }
    }

    func upsert(_ record: StoredAssistantConversation) {
        records.removeAll { $0.id == record.id }
        records.append(record)
        sort()
        save()
    }

    func delete(id: UUID) {
        records.removeAll { $0.id == id }
        save()
    }

    private func sort() {
        records.sort { $0.updatedAt > $1.updatedAt }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? encoder.encode(records).write(to: url, options: .atomic)
    }
}
