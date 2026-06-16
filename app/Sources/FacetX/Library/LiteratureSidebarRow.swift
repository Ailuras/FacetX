import SwiftUI

struct LiteratureSidebarRow: View {
    let topic: TrackPref
    let paperCount: Int

    var body: some View {
        WorkspaceSidebarRow(
            title: topic.name,
            subtitle: "\(paperCount) papers",
            badge: .symbol(topic.icon ?? "tag"),
            tint: MetadataStore.shared.topicColor(topic.name)
        )
    }
}
