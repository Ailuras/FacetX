import SwiftUI

struct PaperRow: View {
    let paper: Paper
    let isSelected: Bool
    let metadata: MetadataStore
    /// `Paper` is a class; passing the store's version gives the row a value to
    /// diff on so in-place status/badge edits re-render it. (See PaperDetailPane.)
    var version: Int = 0

    @State private var hovered = false

    private var rowFill: Color {
        if isSelected { return Color.accentColor.opacity(0.10) }
        if hovered { return Color.primary.opacity(0.035) }
        return FacetTheme.quietPanel
    }

    private var rowStroke: Color {
        if isSelected { return Color.accentColor.opacity(0.45) }
        if hovered { return Color.accentColor.opacity(0.32) }
        return FacetTheme.hairline
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 10) {
                statusDot
                Text(paper.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(.primary)
            }

            HStack(spacing: 8) {
                if !paper.authors.isEmpty {
                    Text(paper.authors.prefix(3).joined(separator: ", "))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                badges
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(rowFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(rowStroke, lineWidth: isSelected ? 1.5 : 1)
        )
        .contentShape(Rectangle())
        .onHover { isHovered in
            withAnimation(.easeOut(duration: 0.15)) {
                hovered = isHovered
            }
        }
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
            if !paper.venueAbbr.isEmpty {
                FacetInfoBadge(
                    text: paper.venueAbbr,
                    systemImage: "building.2",
                    tint: metadata.fieldColor(metadata.field(forAbbr: paper.venueAbbr)),
                    fill: metadata.fieldColor(metadata.field(forAbbr: paper.venueAbbr)).opacity(0.12)
                )
            }
            // Every paper carries a tier (0 = Others / unranked); show it always so
            // unranked papers still read as rated rather than blank.
            FacetInfoBadge(
                text: "T\(paper.tier)",
                systemImage: "star",
                tint: metadata.tierColor(paper.tier),
                fill: metadata.tierColor(paper.tier).opacity(0.12)
            )
            if paper.citedByCount > 0 {
                FacetInfoBadge(
                    text: "\(paper.citedByCount)",
                    systemImage: "quote.bubble",
                    tint: .secondary,
                    fill: Color.secondary.opacity(0.08)
                )
            }
            if !paper.publicationDate.isEmpty {
                FacetInfoBadge(
                    text: paper.publicationDate,
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
