import SwiftUI

struct PaperRow: View {
    let paper: Paper
    let isSelected: Bool
    let metadata: MetadataStore
    var showReason: Bool = false
    /// `Paper` is a class; passing the store's version gives the row a value to
    /// diff on so in-place status/badge edits re-render it. (See PaperDetailPane.)
    var version: Int = 0

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            statusDot

            VStack(alignment: .leading, spacing: 5) {
                Text(paper.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(2)
                    .foregroundStyle(.primary)

                if showReason, !paper.recommendationReason.isEmpty {
                    Label(paper.recommendationReason, systemImage: "sparkles")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                }

                badges

                if !paper.authors.isEmpty {
                    Text(paper.authors.prefix(3).joined(separator: ", "))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.10) : FacetTheme.quietPanel)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(isSelected ? Color.accentColor.opacity(0.45) : FacetTheme.hairline, lineWidth: 1)
        )
        .contentShape(Rectangle())
    }

    private var statusDot: some View {
        Image(systemName: paper.status.iconName)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(paper.status.iconColor)
            .frame(width: 18, height: 18)
            .padding(.top, 1)
    }

    private var badges: some View {
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
    }
}
