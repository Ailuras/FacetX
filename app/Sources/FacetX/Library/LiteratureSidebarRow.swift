import SwiftUI

struct LiteratureSidebarRow: View {
    let topic: TrackPref
    let paperCount: Int

    var tint: Color { MetadataStore.shared.topicColor(topic.name) }

    var body: some View {
        WorkspaceSidebarRow(
            title: topic.name,
            subtitle: "\(paperCount) papers",
            badge: .symbol(topic.icon ?? "tag"),
            tint: tint
        )
    }

    var dragPreview: some View {
        SidebarDragPreview(
            title: topic.name,
            subtitle: "\(paperCount) papers",
            badge: .symbol(topic.icon ?? "tag"),
            tint: tint
        )
    }
}
