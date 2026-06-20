import AppKit
import SwiftUI

struct PaperGraphView: View {
    let papers: [Paper]
    let metadata: MetadataStore
    let onSelectPaper: (Paper) -> Void

    @State private var nodes: [PaperGraphNode] = []
    @State private var links: [PaperGraphLink] = []
    @State private var selectedNodeID: String?
    @State private var hoveredNodeID: String?
    @State private var draggedNodeID: String?
    @State private var selectedStatuses: Set<PaperStatus> = [.pending, .starred, .read]
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var lastCanvasSize: CGSize = .zero

    private var filteredPapers: [Paper] {
        papers
            .filter { selectedStatuses.contains($0.status) }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
    }

    private var graphSignature: String {
        filteredPapers
            .map { paper in
                [
                    paper.id,
                    paper.title,
                    paper.status.rawValue,
                    paper.tags.joined(separator: ","),
                    paper.referencedWorkIDs.joined(separator: ","),
                    paper.relatedWorkIDs.joined(separator: ","),
                    String(format: "%.2f", paper.score)
                ].joined(separator: "|")
            }
            .joined(separator: "\n")
    }

    var body: some View {
        VStack(spacing: 0) {
            graphToolbar
            GeometryReader { geo in
                graphCanvas(size: geo.size)
            }
        }
        .onChange(of: graphSignature) {
            rebuildGraph(in: lastCanvasSize, resetViewport: false)
        }
        .onChange(of: selectedStatuses) {
            rebuildGraph(in: lastCanvasSize, resetViewport: false)
        }
    }

    private var graphToolbar: some View {
        HStack(spacing: 10) {
            Button {
                rebuildGraph(in: lastCanvasSize, resetViewport: true)
            } label: {
                Image(systemName: "arrow.counterclockwise")
            }
            .buttonStyle(.plain)
            .help(L10n.pick("Reset Layout", "重置布局"))
            .hoverCursor(.pointingHand)

            Divider().frame(height: 16)

            Button {
                setScale(scale - 0.15)
            } label: {
                Image(systemName: "minus.magnifyingglass")
            }
            .buttonStyle(.plain)
            .help(L10n.pick("Zoom out", "缩小"))
            .hoverCursor(.pointingHand)

            Text(String(format: "%d%%", Int(scale * 100)))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 42)

            Button {
                setScale(scale + 0.15)
            } label: {
                Image(systemName: "plus.magnifyingglass")
            }
            .buttonStyle(.plain)
            .help(L10n.pick("Zoom in", "放大"))
            .hoverCursor(.pointingHand)

            Button {
                fitGraph(in: lastCanvasSize)
            } label: {
                Image(systemName: "arrow.up.left.and.down.right.magnifyingglass")
            }
            .buttonStyle(.plain)
            .help(L10n.pick("Fit", "适应"))
            .hoverCursor(.pointingHand)

            Divider().frame(height: 16)

            statusFilterView

            if hasPaperRelationLinks {
                Divider().frame(height: 16)
                edgeLegend
            }

            Spacer()

            Text(L10n.pick("\(filteredPapers.count) papers", "\(filteredPapers.count) 篇文献"))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(FacetTheme.quietPanel)
        .overlay(alignment: .bottom) {
            Rectangle().fill(FacetTheme.hairline).frame(height: 1)
        }
    }

    private var statusFilterView: some View {
        HStack(spacing: 6) {
            ForEach(PaperStatus.allCases, id: \.self) { status in
                let isSelected = selectedStatuses.contains(status)
                Button {
                    if isSelected {
                        selectedStatuses.remove(status)
                    } else {
                        selectedStatuses.insert(status)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : status.iconName)
                            .font(.system(size: 10, weight: .semibold))
                        Text(statusTitle(status))
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(isSelected ? status.iconColor : .secondary)
                    .padding(.horizontal, 8)
                    .frame(height: FacetTheme.chipHeight)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(isSelected ? status.iconColor.opacity(0.14) : Color.clear)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(isSelected ? status.iconColor.opacity(0.34) : Color.primary.opacity(0.10), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .hoverCursor(.pointingHand)
            }
        }
    }

    private var hasPaperRelationLinks: Bool {
        links.contains { $0.kind.isPaperRelation }
    }

    private var edgeLegend: some View {
        HStack(spacing: 7) {
            edgeLegendItem(kind: .citation, label: L10n.pick("Citation", "引用"))
            edgeLegendItem(kind: .related, label: L10n.pick("Related", "相关"))
            edgeLegendItem(kind: .citationAndRelated, label: L10n.pick("Both", "两者"))
        }
    }

    private func edgeLegendItem(kind: PaperGraphLinkKind, label: String) -> some View {
        HStack(spacing: 4) {
            Capsule()
                .fill(kind.color(highlighted: false))
                .frame(width: 16, height: max(2, kind.lineWidth(highlighted: false)))
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .fixedSize()
    }

    private func graphCanvas(size: CGSize) -> some View {
        ZStack {
            if filteredPapers.isEmpty {
                ContentUnavailableView(
                    L10n.pick("No papers match these filters", "没有符合筛选条件的文献"),
                    systemImage: "point.3.connected.trianglepath.dotted",
                    description: Text(L10n.pick("Enable another status to populate the graph.", "启用其他状态后可显示图谱。"))
                )
            } else {
                ZStack {
                    gridCanvas
                    linkCanvas
                    ForEach(nodes) { node in
                        nodeView(node)
                            .position(screenPoint(for: node.position))
                    }
                }
                .gesture(panGesture)
                .gesture(zoomGesture)
                .background {
                    PaperGraphScrollMonitor { location, delta in
                        zoom(by: delta > 0 ? 1.08 : 0.92, around: location)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if let node = activeInfoNode {
                        graphInfoCard(for: node)
                            .padding(12)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }
        }
        .coordinateSpace(name: "paperGraphCanvas")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(FacetTheme.canvas)
        .contentShape(Rectangle())
        .clipped()
        .onAppear {
            lastCanvasSize = size
            rebuildGraph(in: size, resetViewport: true)
        }
        .onChange(of: size) { _, newSize in
            lastCanvasSize = newSize
            rebuildGraph(in: newSize, resetViewport: false)
        }
    }

    private var gridCanvas: some View {
        Canvas { context, size in
            let step: CGFloat = 44
            var path = Path()
            let xStart = offset.width.truncatingRemainder(dividingBy: step)
            let yStart = offset.height.truncatingRemainder(dividingBy: step)
            for x in stride(from: xStart - step, through: size.width + step, by: step) {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
            }
            for y in stride(from: yStart - step, through: size.height + step, by: step) {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(path, with: .color(Color.primary.opacity(0.025)), lineWidth: 1)
        }
    }

    private var linkCanvas: some View {
        Canvas { context, _ in
            let nodeMap = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
            let focusIDs = focusedIDs

            for link in links {
                guard let from = nodeMap[link.from], let to = nodeMap[link.to] else { continue }
                let highlighted = focusIDs.contains(from.id) && focusIDs.contains(to.id)
                var path = Path()
                path.move(to: screenPoint(for: from.position))
                path.addLine(to: screenPoint(for: to.position))
                context.stroke(
                    path,
                    with: .color(link.kind.color(highlighted: highlighted)),
                    style: StrokeStyle(lineWidth: link.kind.lineWidth(highlighted: highlighted), lineCap: .round)
                )
            }
        }
    }

    private var panGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard draggedNodeID == nil else { return }
                offset = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                guard draggedNodeID == nil else { return }
                lastOffset = offset
            }
    }

    private var zoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                setScale(lastScale * value, around: canvasCenter)
            }
            .onEnded { _ in
                lastScale = scale
                lastOffset = offset
            }
    }

    private func nodeView(_ node: PaperGraphNode) -> some View {
        let selected = selectedNodeID == node.id
        let hovered = hoveredNodeID == node.id
        let focused = focusedIDs.contains(node.id)
        let color = node.color
        let showLabel = shouldShowInlineLabel(node)
        let dimmed = selectedNodeID != nil && !focused

        return HStack(spacing: showLabel ? 7 : 0) {
            Circle()
                .fill(color)
                .frame(width: node.dotSize, height: node.dotSize)
                .overlay(
                    Circle()
                        .stroke(selected ? Color.accentColor : (hovered ? color.opacity(0.65) : Color.white.opacity(0.28)), lineWidth: selected || hovered ? 2 : 0.75)
                )
                .shadow(color: selected ? Color.accentColor.opacity(0.45) : Color.black.opacity(0.10), radius: selected ? 5 : 1, x: 0, y: 1)

            if showLabel {
                Text(labelText(for: node))
                    .font(.system(size: node.type == .tag ? 10 : 9, weight: node.type == .tag ? .semibold : .medium))
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .frame(maxWidth: selected || hovered || scale > 1.55 ? 220 : 142, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color(NSColor.windowBackgroundColor).opacity(selected || hovered ? 0.94 : 0.76))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(selected ? Color.accentColor.opacity(0.45) : color.opacity(hovered ? 0.34 : 0.16), lineWidth: 1)
                    )
            }
        }
        .opacity(dimmed ? 0.28 : 1)
        .contentShape(Rectangle())
        .hoverCursor(.pointingHand)
        .help(node.fullLabel)
        .onHover { hovering in
            hoveredNodeID = hovering ? node.id : nil
        }
        .onTapGesture {
            selectedNodeID = node.id
            if let paper = node.paper {
                onSelectPaper(paper)
            }
        }
        .gesture(
            DragGesture(coordinateSpace: .named("paperGraphCanvas"))
                .onChanged { value in
                    if draggedNodeID == nil {
                        draggedNodeID = node.id
                    }
                    moveNode(node.id, to: modelPoint(from: value.location))
                }
                .onEnded { _ in
                    draggedNodeID = nil
                }
        )
    }

    private var activeInfoNode: PaperGraphNode? {
        guard let activeID = draggedNodeID ?? hoveredNodeID ?? selectedNodeID else { return nil }
        return nodes.first { $0.id == activeID }
    }

    private func graphInfoCard(for node: PaperGraphNode) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: node.type == .tag ? "tag.fill" : "doc.text.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(node.color)
                Text(node.type == .tag ? L10n.pick("Tag", "标签") : L10n.pick("Paper", "文献"))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
            }

            Text(node.fullLabel)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            switch node.type {
            case .tag:
                tagInfoRows(for: node)
            case .paper:
                paperInfoRows(for: node)
            }
        }
        .padding(11)
        .frame(width: 268, alignment: .leading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(node.color.opacity(0.24), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.12), radius: 18, x: 0, y: 8)
        .allowsHitTesting(false)
    }

    private func tagInfoRows(for node: PaperGraphNode) -> some View {
        let count = filteredPapers.filter { $0.tags.contains(node.fullLabel) }.count
        return VStack(alignment: .leading, spacing: 5) {
            infoLine(systemImage: "doc.text", text: L10n.pick("\(count) linked papers", "\(count) 篇关联文献"))
        }
    }

    private func paperInfoRows(for node: PaperGraphNode) -> some View {
        guard let paper = node.paper else { return AnyView(EmptyView()) }
        return AnyView(
            VStack(alignment: .leading, spacing: 5) {
                if !paper.authors.isEmpty {
                    infoLine(systemImage: "person.2", text: paper.authors.prefix(3).joined(separator: ", "))
                }
                HStack(spacing: 6) {
                    if !paper.venueAbbr.isEmpty {
                        FacetInfoBadge(
                            text: paper.venueAbbr,
                            systemImage: "building.2",
                            tint: metadata.fieldColor(metadata.field(forAbbr: paper.venueAbbr)),
                            fill: metadata.fieldColor(metadata.field(forAbbr: paper.venueAbbr)).opacity(0.12)
                        )
                    }
                    FacetInfoBadge(
                        text: statusTitle(paper.status),
                        systemImage: paper.status.iconName,
                        tint: paper.status.iconColor,
                        fill: paper.status.iconColor.opacity(0.12)
                    )
                    if paper.score > 0 {
                        FacetInfoBadge(
                            text: String(format: "%.0f", paper.score),
                            systemImage: "chart.bar.fill",
                            tint: .secondary,
                            fill: Color.secondary.opacity(0.10)
                        )
                    }
                }
                if !paper.tags.isEmpty {
                    infoLine(systemImage: "tag", text: paper.tags.prefix(4).joined(separator: ", "))
                }
            }
        )
    }

    private func infoLine(systemImage: String, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 12)
            Text(text)
                .font(.system(size: 10))
                .lineLimit(2)
                .foregroundStyle(.secondary)
        }
    }

    private func rebuildGraph(in size: CGSize, resetViewport: Bool) {
        guard size.width > 0, size.height > 0 else { return }
        let graph = PaperGraphBuilder.build(papers: filteredPapers, size: size)
        nodes = graph.nodes
        links = graph.links
        if selectedNodeID.map({ id in !graph.nodes.contains(where: { $0.id == id }) }) == true {
            selectedNodeID = nil
        }
        if resetViewport {
            scale = 1
            lastScale = 1
            offset = .zero
            lastOffset = .zero
        }
    }

    private func fitGraph(in size: CGSize) {
        guard size.width > 0, size.height > 0, !nodes.isEmpty else { return }
        let bounds = nodes.reduce(CGRect.null) { rect, node in
            rect.union(CGRect(x: node.position.x - node.collisionRadius,
                              y: node.position.y - node.collisionRadius,
                              width: node.collisionRadius * 2,
                              height: node.collisionRadius * 2))
        }
        guard !bounds.isNull, bounds.width > 0, bounds.height > 0 else { return }
        let padding: CGFloat = 96
        let sx = (size.width - padding) / bounds.width
        let sy = (size.height - padding) / bounds.height
        let nextScale = clamp(min(sx, sy), min: 0.45, max: 1.6)
        let graphCenter = CGPoint(x: bounds.midX, y: bounds.midY)
        let viewCenter = CGPoint(x: size.width / 2, y: size.height / 2)
        scale = nextScale
        lastScale = nextScale
        offset = CGSize(
            width: viewCenter.x - graphCenter.x * nextScale,
            height: viewCenter.y - graphCenter.y * nextScale
        )
        lastOffset = offset
    }

    private func setScale(_ value: CGFloat) {
        setScale(value, around: canvasCenter)
        lastScale = scale
        lastOffset = offset
    }

    private func modelPoint(from canvasPoint: CGPoint) -> CGPoint {
        CGPoint(
            x: (canvasPoint.x - offset.width) / max(scale, 0.001),
            y: (canvasPoint.y - offset.height) / max(scale, 0.001)
        )
    }

    private func screenPoint(for modelPoint: CGPoint) -> CGPoint {
        CGPoint(
            x: modelPoint.x * scale + offset.width,
            y: modelPoint.y * scale + offset.height
        )
    }

    private var canvasCenter: CGPoint {
        CGPoint(x: lastCanvasSize.width / 2, y: lastCanvasSize.height / 2)
    }

    private func zoom(by factor: CGFloat, around anchor: CGPoint) {
        setScale(scale * factor, around: anchor)
        lastScale = scale
        lastOffset = offset
    }

    private func setScale(_ value: CGFloat, around anchor: CGPoint) {
        let nextScale = clamp(value, min: 0.45, max: 2.8)
        guard abs(nextScale - scale) > 0.0001 else { return }
        let modelAnchor = modelPoint(from: anchor)
        scale = nextScale
        lastScale = nextScale
        offset = CGSize(
            width: anchor.x - modelAnchor.x * nextScale,
            height: anchor.y - modelAnchor.y * nextScale
        )
        lastOffset = offset
    }

    private var focusedIDs: Set<String> {
        guard let focus = selectedNodeID ?? hoveredNodeID else { return Set(nodes.map(\.id)) }
        var ids: Set<String> = [focus]
        for link in links where link.from == focus || link.to == focus {
            ids.insert(link.from)
            ids.insert(link.to)
        }
        return ids
    }

    private func shouldShowInlineLabel(_ node: PaperGraphNode) -> Bool {
        node.type == .tag
    }

    private func labelText(for node: PaperGraphNode) -> String {
        if node.type == .tag || scale > 1.65 {
            return node.fullLabel
        }
        return node.shortLabel
    }

    private func moveNode(_ id: String, to point: CGPoint) {
        guard let index = nodes.firstIndex(where: { $0.id == id }) else { return }
        nodes[index].position = clampedGraphPoint(point, radius: nodes[index].collisionRadius)
        relaxDraggedNeighborhood(fixedID: id)
    }

    private func relaxDraggedNeighborhood(fixedID: String) {
        guard !nodes.isEmpty else { return }
        let size = lastCanvasSize
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let ballRadius = PaperGraphBuilder.ballRadius(for: size)
        let iterations = nodes.count > 90 ? 4 : 7

        for _ in 0..<iterations {
            var deltas = Array(repeating: CGSize.zero, count: nodes.count)

            for i in 0..<nodes.count {
                for j in (i + 1)..<nodes.count {
                    let firstFixed = nodes[i].id == fixedID
                    let secondFixed = nodes[j].id == fixedID
                    let p1 = nodes[i].position
                    let p2 = nodes[j].position
                    var dx = p2.x - p1.x
                    var dy = p2.y - p1.y
                    var distance = sqrt(dx * dx + dy * dy)
                    if distance < 0.1 {
                        dx = CGFloat(((i * 23 + j * 31) % 9) - 4)
                        dy = CGFloat(((i * 29 + j * 13) % 9) - 4)
                        distance = max(1, sqrt(dx * dx + dy * dy))
                    }

                    let minimum = nodes[i].collisionRadius + nodes[j].collisionRadius
                    guard distance < minimum else { continue }
                    let overlap = (minimum - distance) * (firstFixed || secondFixed ? 0.92 : 0.34)
                    let fx = dx / distance * overlap
                    let fy = dy / distance * overlap

                    if firstFixed {
                        deltas[j].width += fx
                        deltas[j].height += fy
                    } else if secondFixed {
                        deltas[i].width -= fx
                        deltas[i].height -= fy
                    } else {
                        deltas[i].width -= fx * 0.5
                        deltas[i].height -= fy * 0.5
                        deltas[j].width += fx * 0.5
                        deltas[j].height += fy * 0.5
                    }
                }
            }

            for link in links {
                guard let fromIndex = nodes.firstIndex(where: { $0.id == link.from }),
                      let toIndex = nodes.firstIndex(where: { $0.id == link.to }) else { continue }
                let fromFixed = nodes[fromIndex].id == fixedID
                let toFixed = nodes[toIndex].id == fixedID
                let from = nodes[fromIndex].position
                let to = nodes[toIndex].position
                let dx = to.x - from.x
                let dy = to.y - from.y
                let distance = max(1, sqrt(dx * dx + dy * dy))
                let target: CGFloat = nodes[fromIndex].type == .paper ? 96 : 76
                let force = (distance - target) * 0.006
                let fx = dx / distance * force
                let fy = dy / distance * force
                if !fromFixed {
                    deltas[fromIndex].width += fx
                    deltas[fromIndex].height += fy
                }
                if !toFixed {
                    deltas[toIndex].width -= fx
                    deltas[toIndex].height -= fy
                }
            }

            for i in nodes.indices where nodes[i].id != fixedID {
                let p = nodes[i].position
                deltas[i].width += (center.x - p.x) * 0.010
                deltas[i].height += (center.y - p.y) * 0.010
                addBallContainmentDelta(
                    for: nodes[i],
                    center: center,
                    ballRadius: ballRadius,
                    into: &deltas[i]
                )

                let limit: CGFloat = 14
                let dx = clamp(deltas[i].width, min: -limit, max: limit)
                let dy = clamp(deltas[i].height, min: -limit, max: limit)
                nodes[i].position = clampedGraphPoint(
                    CGPoint(x: nodes[i].position.x + dx, y: nodes[i].position.y + dy),
                    radius: nodes[i].collisionRadius,
                    size: size
                )
            }
        }
    }

    private func addBallContainmentDelta(for node: PaperGraphNode,
                                         center: CGPoint,
                                         ballRadius: CGFloat,
                                         into delta: inout CGSize) {
        let px = node.position.x - center.x
        let py = node.position.y - center.y
        let distance = max(1, sqrt(px * px + py * py))
        let allowed = max(48, ballRadius - node.collisionRadius)
        guard distance > allowed else { return }
        let pull = (distance - allowed) * 0.11
        delta.width -= px / distance * pull
        delta.height -= py / distance * pull
    }

    private func clampedGraphPoint(_ point: CGPoint, radius: CGFloat, size: CGSize? = nil) -> CGPoint {
        let bounds = size ?? lastCanvasSize
        guard bounds.width > 0, bounds.height > 0 else { return point }
        let margin = radius + 18
        return CGPoint(
            x: clamp(point.x, min: margin, max: bounds.width - margin),
            y: clamp(point.y, min: margin, max: bounds.height - margin)
        )
    }

    private func statusTitle(_ status: PaperStatus) -> String {
        switch status {
        case .pending: return L10n.pick("Pending", "待读")
        case .starred: return L10n.pick("Starred", "收藏")
        case .read: return L10n.pick("Read", "已读")
        case .skip: return L10n.pick("Skipped", "已忽略")
        }
    }

    private func clamp(_ value: CGFloat, min minValue: CGFloat, max maxValue: CGFloat) -> CGFloat {
        Swift.max(minValue, Swift.min(maxValue, value))
    }
}

private enum PaperGraphBuilder {
    static func build(papers: [Paper], size: CGSize) -> (nodes: [PaperGraphNode], links: [PaperGraphLink]) {
        guard !papers.isEmpty else { return ([], []) }

        let width = max(size.width, 520)
        let height = max(size.height, 360)
        let graphSize = CGSize(width: width, height: height)
        let center = CGPoint(x: width / 2, y: height / 2)
        let ballRadius = ballRadius(for: graphSize)
        let tagCounts = Dictionary(grouping: papers.flatMap(\.tags), by: { $0 })
            .mapValues(\.count)
        let selectedTags = tagCounts
            .sorted { lhs, rhs in
                if lhs.value != rhs.value { return lhs.value > rhs.value }
                return lhs.key.localizedCaseInsensitiveCompare(rhs.key) == .orderedAscending
            }
            .prefix(24)
            .map(\.key)
        let selectedTagSet = Set(selectedTags)
        let localPaperIDs = Set(papers.map(\.id))
        let needsUntagged = papers.contains { paper in
            paper.tags.allSatisfy { !selectedTagSet.contains($0) }
        }
        let clusterNames = selectedTags + (needsUntagged ? [PaperGraphNode.untaggedLabel] : [])
        let clusterCount = max(1, clusterNames.count)
        let tagRadius = ballRadius * (clusterCount <= 4 ? 0.30 : 0.42)
        let paperRadius = max(44, ballRadius * 0.18)
        var clusterAnchors: [String: CGPoint] = [:]
        var nodes: [PaperGraphNode] = []
        var links: [PaperGraphLink] = []

        for (idx, tag) in clusterNames.enumerated() {
            let angle = clusterAngle(index: idx, count: clusterCount)
            let anchor = CGPoint(
                x: center.x + cos(angle) * tagRadius,
                y: center.y + sin(angle) * tagRadius
            )
            clusterAnchors[tag] = anchor
            if tag != PaperGraphNode.untaggedLabel {
                nodes.append(PaperGraphNode(
                    id: PaperGraphNode.tagID(tag),
                    fullLabel: tag,
                    shortLabel: abbreviated(tag, limit: 22),
                    type: .tag,
                    position: anchor,
                    color: .blue,
                    paper: nil,
                    clusterKey: tag,
                    labelPriority: 1
                ))
            }
        }

        let papersByCluster = Dictionary(grouping: papers) { paper -> String in
            primaryCluster(for: paper, selectedTags: selectedTags) ?? PaperGraphNode.untaggedLabel
        }

        for cluster in clusterNames {
            let clusterPapers = (papersByCluster[cluster] ?? [])
                .sorted { lhs, rhs in
                    if lhs.score != rhs.score { return lhs.score > rhs.score }
                    return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                }
            let anchor = clusterAnchors[cluster] ?? center
            let spread = min(max(paperRadius, CGFloat(clusterPapers.count) * 5 + 24), ballRadius * 0.34)

            for (idx, paper) in clusterPapers.enumerated() {
                let angle = clusterAngle(index: idx, count: max(1, clusterPapers.count))
                let ring = spread + CGFloat(idx % 4) * 10
                let position = CGPoint(
                    x: anchor.x + cos(angle) * ring,
                    y: anchor.y + sin(angle) * ring
                )
                let priority = labelPriority(for: paper, index: idx)
                nodes.append(PaperGraphNode(
                    id: PaperGraphNode.paperID(paper.id),
                    fullLabel: paper.title,
                    shortLabel: abbreviated(paper.title, limit: 28),
                    type: .paper,
                    position: position,
                    color: paper.status.iconColor,
                    paper: paper,
                    clusterKey: cluster,
                    labelPriority: priority
                ))

                for tag in paper.tags.filter({ selectedTagSet.contains($0) }).prefix(4) {
                    links.append(PaperGraphLink(from: PaperGraphNode.paperID(paper.id), to: PaperGraphNode.tagID(tag), kind: .tag))
                }
            }
        }

        links.append(contentsOf: paperRelationLinks(papers: papers, localPaperIDs: localPaperIDs))

        let laidOut = relax(nodes: nodes, links: links, anchors: clusterAnchors, center: center, size: graphSize, ballRadius: ballRadius)
        return (laidOut, links)
    }

    static func ballRadius(for size: CGSize) -> CGFloat {
        max(150, min(size.width, size.height) * 0.42)
    }

    private static func relax(nodes: [PaperGraphNode],
                              links: [PaperGraphLink],
                              anchors: [String: CGPoint],
                              center: CGPoint,
                              size: CGSize,
                              ballRadius: CGFloat) -> [PaperGraphNode] {
        var result = nodes
        let indexByID = Dictionary(uniqueKeysWithValues: result.enumerated().map { ($0.element.id, $0.offset) })
        let iterations = result.count > 110 ? 72 : 96

        for iteration in 0..<iterations {
            var deltas = Array(repeating: CGSize.zero, count: result.count)
            let progress = CGFloat(iteration) / CGFloat(max(1, iterations - 1))
            let cooling = 1 - progress * 0.42

            for i in result.indices {
                let anchor = anchors[result[i].clusterKey] ?? center
                let strength: CGFloat = result[i].type == .tag ? 0.012 : 0.004
                deltas[i].width += (anchor.x - result[i].position.x) * strength
                deltas[i].height += (anchor.y - result[i].position.y) * strength

                let gravity: CGFloat = result[i].type == .tag ? 0.014 : 0.010
                deltas[i].width += (center.x - result[i].position.x) * gravity
                deltas[i].height += (center.y - result[i].position.y) * gravity
                addBallContainmentDelta(for: result[i], center: center, ballRadius: ballRadius, into: &deltas[i])
            }

            for link in links {
                guard let fromIndex = indexByID[link.from], let toIndex = indexByID[link.to] else { continue }
                let from = result[fromIndex].position
                let to = result[toIndex].position
                let dx = to.x - from.x
                let dy = to.y - from.y
                let distance = max(1, sqrt(dx * dx + dy * dy))
                let target: CGFloat = result[fromIndex].type == .paper ? 78 : 64
                let force = (distance - target) * 0.013
                let fx = dx / distance * force
                let fy = dy / distance * force
                deltas[fromIndex].width += fx
                deltas[fromIndex].height += fy
                deltas[toIndex].width -= fx
                deltas[toIndex].height -= fy
            }

            for i in 0..<result.count {
                for j in (i + 1)..<result.count {
                    let p1 = result[i].position
                    let p2 = result[j].position
                    var dx = p2.x - p1.x
                    var dy = p2.y - p1.y
                    var distance = sqrt(dx * dx + dy * dy)
                    if distance < 0.1 {
                        dx = CGFloat(((i * 37 + j * 17) % 11) - 5)
                        dy = CGFloat(((i * 19 + j * 29) % 13) - 6)
                        distance = max(1, sqrt(dx * dx + dy * dy))
                    }
                    let minimum = result[i].collisionRadius + result[j].collisionRadius
                    guard distance < minimum else { continue }
                    let overlap = (minimum - distance) * 0.66
                    let fx = dx / distance * overlap
                    let fy = dy / distance * overlap
                    deltas[i].width -= fx
                    deltas[i].height -= fy
                    deltas[j].width += fx
                    deltas[j].height += fy
                }
            }

            for i in result.indices {
                let limit: CGFloat = 20 * cooling
                let dx = max(-limit, min(limit, deltas[i].width))
                let dy = max(-limit, min(limit, deltas[i].height))
                let margin = result[i].collisionRadius + 18
                result[i].position = CGPoint(
                    x: max(margin, min(size.width - margin, result[i].position.x + dx)),
                    y: max(margin, min(size.height - margin, result[i].position.y + dy))
                )
            }
        }

        return result
    }

    private static func paperRelationLinks(papers: [Paper], localPaperIDs: Set<String>) -> [PaperGraphLink] {
        var kindsByPair: [PaperGraphPair: Set<PaperGraphPaperRelation>] = [:]

        for paper in papers {
            for targetID in paper.referencedWorkIDs where localPaperIDs.contains(targetID) {
                addPaperRelation(.citation, from: paper.id, to: targetID, into: &kindsByPair)
            }
            for targetID in paper.relatedWorkIDs where localPaperIDs.contains(targetID) {
                addPaperRelation(.related, from: paper.id, to: targetID, into: &kindsByPair)
            }
        }

        return kindsByPair.map { pair, kinds in
            let kind: PaperGraphLinkKind
            if kinds.contains(.citation), kinds.contains(.related) {
                kind = .citationAndRelated
            } else if kinds.contains(.citation) {
                kind = .citation
            } else {
                kind = .related
            }
            return PaperGraphLink(
                from: PaperGraphNode.paperID(pair.first),
                to: PaperGraphNode.paperID(pair.second),
                kind: kind
            )
        }
        .sorted { lhs, rhs in
            if lhs.kind.sortRank != rhs.kind.sortRank { return lhs.kind.sortRank < rhs.kind.sortRank }
            return lhs.id < rhs.id
        }
    }

    private static func addPaperRelation(_ relation: PaperGraphPaperRelation,
                                         from sourceID: String,
                                         to targetID: String,
                                         into kindsByPair: inout [PaperGraphPair: Set<PaperGraphPaperRelation>]) {
        guard sourceID != targetID else { return }
        kindsByPair[PaperGraphPair(sourceID, targetID), default: []].insert(relation)
    }

    private static func addBallContainmentDelta(for node: PaperGraphNode,
                                                center: CGPoint,
                                                ballRadius: CGFloat,
                                                into delta: inout CGSize) {
        let px = node.position.x - center.x
        let py = node.position.y - center.y
        let distance = max(1, sqrt(px * px + py * py))
        let allowed = max(52, ballRadius - node.collisionRadius)
        guard distance > allowed else { return }
        let pull = (distance - allowed) * 0.16
        delta.width -= px / distance * pull
        delta.height -= py / distance * pull
    }

    private static func primaryCluster(for paper: Paper, selectedTags: [String]) -> String? {
        for tag in selectedTags where paper.tags.contains(tag) {
            return tag
        }
        return nil
    }

    private static func labelPriority(for paper: Paper, index: Int) -> CGFloat {
        var priority: CGFloat = 0.18
        if paper.status == .starred { priority += 0.42 }
        if paper.isRecommended { priority += 0.20 }
        priority += CGFloat(min(max(paper.score, 0), 100)) / 250
        if index < 3 { priority += 0.22 }
        return min(priority, 1)
    }

    private static func clusterAngle(index: Int, count: Int) -> CGFloat {
        guard count > 1 else { return -.pi / 2 }
        return -.pi / 2 + CGFloat(index) * 2 * .pi / CGFloat(count)
    }

    private static func abbreviated(_ text: String, limit: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed }
        let end = trimmed.index(trimmed.startIndex, offsetBy: max(1, limit - 1))
        return String(trimmed[..<end]) + "..."
    }
}

private struct PaperGraphNode: Identifiable, Equatable {
    enum NodeType {
        case paper, tag
    }

    static let untaggedLabel = "__untagged__"

    let id: String
    let fullLabel: String
    let shortLabel: String
    let type: NodeType
    var position: CGPoint
    let color: Color
    let paper: Paper?
    let clusterKey: String
    let labelPriority: CGFloat

    var dotSize: CGFloat { type == .tag ? 12 : 10 }

    var collisionRadius: CGFloat {
        switch type {
        case .tag:
            return max(42, min(86, CGFloat(fullLabel.count) * 4.8 + 24))
        case .paper:
            return labelPriority > 0.82 ? 58 : 31
        }
    }

    static func paperID(_ id: String) -> String { "paper:\(id)" }
    static func tagID(_ tag: String) -> String { "tag:\(tag)" }

    static func == (lhs: PaperGraphNode, rhs: PaperGraphNode) -> Bool {
        lhs.id == rhs.id &&
            lhs.fullLabel == rhs.fullLabel &&
            lhs.shortLabel == rhs.shortLabel &&
            lhs.type == rhs.type &&
            lhs.position == rhs.position &&
            lhs.clusterKey == rhs.clusterKey &&
            lhs.labelPriority == rhs.labelPriority &&
            lhs.paper?.id == rhs.paper?.id
    }
}

private enum PaperGraphPaperRelation: Hashable {
    case citation, related
}

private enum PaperGraphLinkKind: Equatable {
    case tag
    case citation
    case related
    case citationAndRelated

    var sortRank: Int {
        switch self {
        case .tag: return 0
        case .related: return 1
        case .citation: return 2
        case .citationAndRelated: return 3
        }
    }

    var isPaperRelation: Bool {
        self != .tag
    }

    func color(highlighted: Bool) -> Color {
        switch self {
        case .tag:
            return highlighted ? Color.accentColor.opacity(0.55) : Color.primary.opacity(0.075)
        case .citation:
            return Color.orange.opacity(highlighted ? 0.78 : 0.38)
        case .related:
            return Color.teal.opacity(highlighted ? 0.72 : 0.34)
        case .citationAndRelated:
            return Color.pink.opacity(highlighted ? 0.82 : 0.50)
        }
    }

    func lineWidth(highlighted: Bool) -> CGFloat {
        switch self {
        case .tag:
            return highlighted ? 1.4 : 0.75
        case .citation:
            return highlighted ? 2.1 : 1.2
        case .related:
            return highlighted ? 1.9 : 1.1
        case .citationAndRelated:
            return highlighted ? 2.8 : 1.8
        }
    }
}

private struct PaperGraphPair: Hashable {
    let first: String
    let second: String

    init(_ lhs: String, _ rhs: String) {
        if lhs.localizedStandardCompare(rhs) == .orderedDescending {
            first = rhs
            second = lhs
        } else {
            first = lhs
            second = rhs
        }
    }
}

private struct PaperGraphLink: Identifiable, Equatable {
    let from: String
    let to: String
    let kind: PaperGraphLinkKind

    var id: String { "\(from)->\(to):\(kind)" }
}

private struct PaperGraphScrollMonitor: NSViewRepresentable {
    let onScroll: (CGPoint, CGFloat) -> Void

    func makeNSView(context: Context) -> MonitorView {
        let view = MonitorView()
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ nsView: MonitorView, context: Context) {
        nsView.onScroll = onScroll
    }

    static func dismantleNSView(_ nsView: MonitorView, coordinator: ()) {
        nsView.removeMonitor()
    }

    final class MonitorView: NSView {
        var onScroll: ((CGPoint, CGFloat) -> Void)?
        private var monitor: Any?

        override var isFlipped: Bool { true }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            installMonitor()
        }

        func removeMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        private func installMonitor() {
            removeMonitor()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, self.window != nil else { return event }
                let location = self.convert(event.locationInWindow, from: nil)
                guard self.bounds.contains(location) else { return event }
                let delta = event.scrollingDeltaY
                guard abs(delta) > 0.01 else { return nil }
                self.onScroll?(location, delta)
                return nil
            }
        }
    }
}
