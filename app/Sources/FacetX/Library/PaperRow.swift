import SwiftUI

struct PaperRow: View {
    let paper: Paper
    let isSelected: Bool
    let metadata: MetadataStore
    /// `Paper` is a class; passing the store's version gives the row a value to
    /// diff on so in-place status/badge edits re-render it. (See PaperDetailPane.)
    var version: Int = 0
    /// Number of projects this paper has been linked to (passed from the parent
    /// view which holds the `paperLinks` map). Shows a folder corner badge.
    var linkedProjectCount: Int = 0

    @State private var hovered = false

    private var hasLocalPDF: Bool {
        guard let path = paper.pdfLocalPath else { return false }
        return !path.isEmpty
    }

    private var badgeCount: Int {
        (linkedProjectCount > 0 ? 1 : 0) + (hasLocalPDF ? 1 : 0)
    }

    /// Extra trailing padding on the title text so it doesn't slide under the
    /// floating corner badges. Each badge is 16 pt wide with 3 pt inter-gap.
    private var titleTrailingPadding: CGFloat {
        guard badgeCount > 0 else { return 0 }
        return CGFloat(badgeCount) * 16 + CGFloat(badgeCount - 1) * 3 + 4
    }

    private var rowFill: Color {
        if isSelected { return FacetTheme.softAccent }
        if hovered { return Color.primary.opacity(0.035) }
        return FacetTheme.quietPanel
    }

    private var rowStroke: Color {
        if hovered { return Color.primary.opacity(0.12) }
        return FacetTheme.hairline
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top, spacing: 10) {
                    statusDot
                    Text(paper.title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(.primary)
                        .padding(.trailing, titleTrailingPadding)
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

            // Corner badges: project link (yellow folder) and/or local PDF (green doc).
            // Placed in an HStack so they sit side-by-side in the topTrailing corner.
            HStack(spacing: 3) {
                if linkedProjectCount > 0 {
                    projectCornerBadge
                }
                if hasLocalPDF {
                    pdfCornerBadge
                }
            }
            .opacity(badgeCount > 0 ? 1 : 0)
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
                .stroke(rowStroke, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onHover { isHovered in
            withAnimation(.easeOut(duration: 0.15)) {
                hovered = isHovered
            }
        }
    }

    @ViewBuilder
    private var statusDot: some View {
        if paper.status != .starred {
            Image(systemName: paper.status.iconName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(paper.status.iconColor)
                .frame(width: 18, height: 18)
                .padding(.top, 1)
        }
    }

    private var projectCornerBadge: some View {
        Image(systemName: "folder.fill")
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(.yellow)
            .frame(width: 16, height: 16)
            .background(Color.yellow.opacity(0.13))
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(Color.yellow.opacity(0.28), lineWidth: 1)
            )
    }

    private var pdfCornerBadge: some View {
        Image(systemName: "doc.fill")
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(.green)
            .frame(width: 16, height: 16)
            .background(Color.green.opacity(0.13))
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(Color.green.opacity(0.24), lineWidth: 1)
            )
            .padding(.top, -1)
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
                systemImage: "number",
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
        }
    }
}
