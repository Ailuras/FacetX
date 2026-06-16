import SwiftUI

struct PaperRow: View {
    let paper: Paper
    let isSelected: Bool
    let metadata: MetadataStore

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(paper.title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(2)
                .foregroundStyle(.primary)

            HStack(spacing: 6) {
                if !paper.venueAbbr.isEmpty, paper.venueAbbr != "Others" {
                    FacetInfoBadge(
                        text: paper.venueAbbr,
                        systemImage: "building.2",
                        tint: metadata.fieldColor(metadata.field(forAbbr: paper.venueAbbr)),
                        fill: metadata.fieldColor(metadata.field(forAbbr: paper.venueAbbr)).opacity(0.12)
                    )
                }

                if paper.tier > 0 {
                    FacetInfoBadge(
                        text: "T\(paper.tier)",
                        systemImage: "star",
                        tint: metadata.tierColor(paper.tier),
                        fill: metadata.tierColor(paper.tier).opacity(0.12)
                    )
                }

                if paper.citedByCount > 0 {
                    FacetInfoBadge(
                        text: "\(paper.citedByCount)",
                        systemImage: "quote.bubble",
                        tint: .secondary,
                        fill: Color.secondary.opacity(0.08)
                    )
                }

                if let year = paper.publicationYear {
                    FacetInfoBadge(
                        text: "\(year)",
                        systemImage: "calendar",
                        tint: .secondary,
                        fill: Color.secondary.opacity(0.08)
                    )
                }

                if let path = paper.pdfLocalPath, !path.isEmpty {
                    FacetInfoBadge(
                        text: "PDF",
                        systemImage: "doc",
                        tint: .green,
                        fill: Color.green.opacity(0.12)
                    )
                }
            }

            if !paper.authors.isEmpty {
                Text(paper.authors.prefix(3).joined(separator: ", "))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.08) : Color.clear)
        )
        .contentShape(Rectangle())
    }
}
